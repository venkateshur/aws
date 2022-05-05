import spark.implicits._
  val rawJson = spark.read.textFile("s3://raw.json").rdd.zipWithIndex().toDF("value", "index")
    .filter(!col("index").isin(Seq(0,1,2,3,4,5,6,7,8):_*)).cache()
  
  val indexValues = rawJson.select(min(col("index")), max(col("index")))
    .collect().map(row => (row.getLong(0), row.getLong(1))).toSeq(0)

  val parse = rawJson.withColumn("value",
    when(col("index") === indexValues._1,
      concat_ws("", lit("{"), col("value"))).otherwise(col("value"))).select("value")
    .filter(col("value").isNotNull)
    .withColumn("value", concat_ws("", collect_list(trim(col("value")))))
  
  val networkJson = spark.read.option("multiLine", "true").json(parse.rdd.map(_.getString(0)))
    .withColumn("explode", explode(col("in_network")))
    .drop("in_network").select(col("explode.*"))
