WITH cohort AS (
  SELECT DISTINCT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON CAST(i.subject_id AS STRING) = d.subject_id
    AND CAST(i.hadm_id AS STRING) = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND (
      (d.icd_version = 'ICD-9' AND d.icd_code = '4275')
      OR (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I46%')
    )
),
scores AS (
  SELECT
    ce.stay_id,
    COUNT(*) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort c
    ON ce.subject_id = c.subject_id
    AND ce.stay_id = c.stay_id
  WHERE ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (
      -- HR
      211, 220045,
      -- RR
      618, 220210,
      -- Temp (C)
      676, 223761,
      -- SBP
      51, 442, 455, 6701, 220179, 225309,
      -- DBP
      836, 844, 855, 220180, 225310,
      -- SpO2
      646, 220277
    )
    AND ce.valuenum IS NOT NULL
    AND (
      -- Abnormal HR
      (ce.itemid IN (211, 220045) AND (ce.valuenum < 60 OR ce.valuenum > 100))
      -- Abnormal RR
      OR (ce.itemid IN (618, 220210) AND (ce.valuenum < 12 OR ce.valuenum > 20))
      -- Abnormal Temp
      OR (ce.itemid IN (676, 223761) AND (ce.valuenum < 36 OR ce.valuenum > 38))
      -- Abnormal SBP
      OR (ce.itemid IN (51, 442, 455, 6701, 220179, 225309) AND (ce.valuenum < 90 OR ce.valuenum > 140))
      -- Abnormal DBP
      OR (ce.itemid IN (836, 844, 855, 220180, 225310) AND (ce.valuenum < 60 OR ce.valuenum > 90))
      -- Abnormal SpO2
      OR (ce.itemid IN (646, 220277) AND ce.valuenum < 92)
    )
  GROUP BY ce.stay_id
),
scored_cohort AS (
  SELECT
    c.*,
    COALESCE(s.instability_score, 0) AS instability_score
  FROM cohort c
  LEFT JOIN scores s
    ON c.stay_id = s.stay_id
),
ranked AS (
  SELECT
    *,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM scored_cohort
)
SELECT
  ROUND(AVG(CASE WHEN instability_score <= 70 THEN 1.0 ELSE 0 END) * 100, 2) AS percentile_for_70,
  ROUND(AVG(CASE WHEN decile = 1 THEN los END), 2) AS mean_los_top_decile,
  ROUND(AVG(CASE WHEN decile = 1 THEN CAST(hospital_expire_flag AS FLOAT64) END), 3) AS mortality_top_decile
FROM ranked;