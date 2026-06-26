curl -X GET "https://dev-pp-logs.supp.fitness/_cluster/health" \
  -u admin:roqkf0531! \
  -k

curl -X GET "https://dev-pp-logs.supp.fitness/_cat/indices?v" \
  -u admin:roqkf0531! \
  -k

--
curl -X GET "https://dev-pp-logs.supp.fitness/api/console/proxy?path=_cluster%2Fhealth&method=GET" \
  -u admin:roqkf0531! \
  -H "osd-xsrf: true" \
  -k

--
curl -X GET "https://dev-pp-logs.supp.fitness/" \
  -u admin:roqkf0531! \
  -k -v

--
curl -X GET "http://localhost:9200/_cluster/health" -u admin:roqkf0531!
curl -X GET "https://dev-pp-logs.supp.fitness:9200/_cluster/health" -u admin:roqkf0531!


curl -X GET "https://localhost:9200/_cluster/health" -u admin:roqkf0531! -k


curl -k -u admin:pw "https://localhost:9200/_cat/indices?v&s=index"

curl -X GET "http://localhost:9200/_cluster/health" -u admin:ttttf0531!
curl: (52) Empty reply from server