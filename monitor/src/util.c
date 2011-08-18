/* monitor.c */

#include<stdio.h>
#include<string.h>
#include<stdlib.h>
#include<ctype.h>
#include<json/json.h>
#include<sqlite3.h>

// To Handle any partial sends
int 
sendall(int s, char *buf, int total) 
{
  int sendbytes = 0;
  int bytesleft = total;
  int n = 0;

  while( sendbytes < total) {
        if( (n = send(s, buf+sendbytes, bytesleft, 0)) == -1) {
          perror("send");
          break;
        }
        sendbytes = sendbytes + n;
        bytesleft = bytesleft + n;
  }
  return n==-1? -1: 0;
}

static
int
callback(void *NotUsed, int argc, char **argv, char **azColName)
{
  int i;
  for(i=1; i<argc; i++){
    printf("%s = %s\n", azColName[i], argv[i] ? argv[i] : "NULL");
  }
  printf("\n");
  return 0;
}

void
array_list_print(array_list *ls)
{
  printf("[");
  for(int i = 0; i < array_list_length(ls); i++){
    printf("%d: %s", i, array_list_get_idx(ls, i));
    if(i != array_list_length(ls) -1) printf(",");
  }
  printf(" ]\n");
}


void update_db(json_object *jobj, sqlite3 *db)
{
  char *sqlite_cmd = malloc(sizeof(char)*1024);
  strcpy(sqlite_cmd, "INSERT OR REPLACE INTO WWSTATS(");
  char *values = malloc(sizeof(char)*1024);
  strcpy(values, " VALUES('");
  int rc;

  json_object_object_foreach(jobj, key, value){
    strcat(sqlite_cmd, key);
    strcat(sqlite_cmd,",");
    strcat(values, json_object_get_string(value));
    strcat(values, "','");
  }
  sqlite_cmd[strlen(sqlite_cmd)-1] = ')';
  
  strcat(sqlite_cmd, values);
  
  sqlite_cmd[strlen(sqlite_cmd)-2] = ')';
  sqlite_cmd[strlen(sqlite_cmd)-1] = '\0';
  printf("Command was: %s\n", sqlite_cmd);

  rc = sqlite3_exec(db, sqlite_cmd,callback, 0, 0); 

  if( rc!=SQLITE_OK ){
    fprintf(stderr, "SQL error: %s\n", 0);
    sqlite3_free(0);
  }

  free(sqlite_cmd);
  free(values);
}

void json_parse_complete(json_object *jobj);


void
json_parse_complete(json_object *jobj){
  enum json_type type;
  json_object_object_foreach(jobj, key, val) {
    type = json_object_get_type(val);
    switch (type) {
    case json_type_string: 
      printf("%s : %s\n", key, json_object_get_string(val));
      break;
    case json_type_object:
      json_parse_complete(json_object_object_get(jobj, key));
      printf("\n");
      break;
    }
  }
} 


void
json_parse(json_object *jobj){
  json_object_object_foreach(jobj, key, value){
    printf("%s: %s\n", key, json_object_get_string(value));
  }
}


/*
Removes the new line character from the end of the 
string if it exists.
*/
char *chop(char *s){
    if(s[strlen(s)-1] == '\n') s[strlen(s)-1] = '\0';
    return s;
}


/*
More efficient version of file_parser. Instead of accessing a file 
number of keys times, opens a file only once and collects
data as it parses. Upon successful location of the key and value,
function places kv-pair in json_object whose pointer is the return
value.
*/
json_object *fast_data_parser(char *file_name, array_list *keys, int num_keys){
  FILE *fp;
  json_object *jobj = json_object_new_object();
  int i, keys_found = 0;
  if(fp = fopen(file_name, "r")){
    char *line = malloc(sizeof(char)*100);
    char *data = malloc(sizeof(char)*100);
    while(fgets(line, 100,fp)){
      for(i = 0; i < num_keys; i++){
	if(data = strstr(line, array_list_get_idx(keys, i))){
	  while(*data != ':') data++;
	  while(isspace(*data) || ispunct(*data)) data ++;
	  json_object_object_add(jobj, array_list_get_idx(keys, i), (json_object *) json_object_new_string(chop(data)));
	  keys_found += 1;
	  if(keys_found == num_keys) break; 
	}
      }
    }
    free(line);
    free(data);
    fclose(fp);
    return jobj;
  } else {
    printf("I/O ERROR: could not access file\n");
    return NULL;
  }
}


struct cpu_data{
  long tj;
  long wj;
};



static int
json_from_db2(void *void_json, int argc, char **argv, char **azColName)
{
  int i;
  json_object *json_db = (json_object *) void_json;
  json_object *tmp = json_object_new_object();
  char *key_buf = malloc(sizeof(char)*1024);
  for(i = 0; i < argc; i++){
    json_object_object_add(tmp, azColName[i], json_object_new_string(argv[i]));
  }  
  printf("argv[0] = %s\n", argv[0]);
  printf("argv[1] = %s\n", argv[1]);
  json_object_object_add(json_db, argv[0], tmp); // REQUIRE ROWID IS FIRST ARG
  free(key_buf);
  return 0;
}


static int
json_from_db(void *void_json, int argc, char **argv, char **azColName)
{
  int i;
  json_object *json_db = (json_object *) void_json;
  json_object *tmp = json_object_new_object();
  printf("\nargv[0] = %s\n", argv[0]);
  for(i = 0; i < argc; i++){
    json_object_object_add(tmp, azColName[i], (json_object *) json_object_new_string(argv[i]));
  }
  json_object_object_add(json_db, argv[0], tmp);
  return 0;
}

long
get_jiffs(struct cpu_data *cd)
{
  long total_jiffs, work_jiffs;
  int iters, i;
  total_jiffs = 0;
  work_jiffs = 0;
  FILE *fp;
  if(fp = fopen("/proc/stat", "r")){
    char *line = malloc(sizeof(char)*100);
    char *data = malloc(sizeof(char)*100);
    while(fgets(line, 100, fp)){
      if(data = strstr(line, "cpu")){
	char * result = NULL;
	result = strtok(data, " ");
	while(result != NULL){
	  chop(result);
	  if(strcmp("cpu", result)){
	    if(i++ < 3) work_jiffs += atoi(result); // calculating work_jiffs
	    total_jiffs += atoi(result); // calculating total_jiffs
	  }
	  result = strtok(NULL, " ");
	}
      }
      i = 0; // reset i to get each cpu's work_jiffs added
    }
    free(line);
    free(data);
    fclose(fp);
    cd->tj = total_jiffs;
    cd->wj = work_jiffs;

    return 0;
  } else {
    printf("I/O ERROR: could not access file\n");
    return -1;
  }
}


float
get_cpu_util()
{
  struct cpu_data *fin = malloc(sizeof(struct cpu_data *));
  struct cpu_data *init = malloc(sizeof(struct cpu_data *));
  get_jiffs(init);
  sleep(2);
  get_jiffs(fin);
  
  long work_diff = fin->wj - init->wj;
  long  total_diff = fin->tj - init->tj;
  
  free(fin);
  free(init);
  
  return (float) work_diff/total_diff*100;

}



void
update_db2(json_object *jobj, sqlite3 *db)
{
  
  int rc;
  printf("Starting foreach loop...\n");
 
  json_object_object_foreach(jobj, key, value){
    char *sqlite_cmd = malloc(sizeof(char)*1024);
    strcpy(sqlite_cmd, "INSERT OR REPLACE INTO WWSTATS(NodeName, key, value) ");
    char *values = malloc(sizeof(char)*1024);
    strcpy(values, " VALUES('");
    json_object *tmp = value;
    json_object *jstring = json_object_object_get(tmp, "NodeName");
    json_parse_complete(tmp);
    strcat(values, json_object_get_string(jstring));
    strcat(values, "' , '");
    
    jstring = json_object_object_get(tmp, "key");
    strcat(values, json_object_get_string(jstring));
    strcat(values, "' , '");
    
    jstring = json_object_object_get(tmp, "value");
    strcat(values, json_object_get_string(jstring));
    strcat(values, "' )");
    
    strcat(sqlite_cmd, values);
    printf("Command was: %s\n", sqlite_cmd);

    rc = sqlite3_exec(db, sqlite_cmd,callback, 0, 0); 
    if( rc!=SQLITE_OK ){
      fprintf(stderr, "SQL error: %s\n", 0);
      sqlite3_free(0);
    }
    
    free(sqlite_cmd);
    free(values);
  }

}
