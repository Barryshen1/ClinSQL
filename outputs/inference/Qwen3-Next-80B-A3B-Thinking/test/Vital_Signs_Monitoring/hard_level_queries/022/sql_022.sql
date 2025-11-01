WITH acute_respiratory_failure AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.long_title LIKE '%acute respiratory failure%'
),
cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    a.hadm_id,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN acute_respiratory_failure arf
    ON a.hadm_id = arf.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 85 AND 95
),
instability_scores AS (
  SELECT 
    stay_id,
    SUM(std_dev) AS score
  FROM (
    SELECT 
      c.stay_id,
      c.itemid,
      STDDEV(c.valuenum) AS std_dev
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN cohort co ON c.stay_id = co.stay_id
    WHERE c.charttime BETWEEN co.intime AND co.intime + INTERVAL 24 HOUR
      AND c.itemid IN (220045, 220050, 220210)
      AND c.valuenum IS NOT NULL
    GROUP BY c.stay_id, c.itemid
  ) AS item_stddevs
  GROUP BY stay_id
),
quartiles AS (
  SELECT 
    stay_id,
    score,
    NTILE(4) OVER (ORDER BY score DESC) AS quartile
  FROM instability_scores
),
top_quartile AS (
  SELECT 
    AVG(cohort.los) AS avg_los,
    AVG(cohort.hospital_expire_flag) AS mortality
  FROM quartiles
  JOIN cohort ON quartiles.stay_id = cohort.stay_id
  WHERE quartiles.quartile = 1
),
percentile_rank AS (
  SELECT 
    SAFE_DIVIDE(COUNTIF(score <= 85) * 100.0, COUNT(*)) AS percentile_rank
  FROM instability_scores
)
SELECT 
  pr.percentile_rank,
  tq.avg_los,
  tq.mortality
FROM percentile_rank pr
CROSS JOIN top_quartile tq;