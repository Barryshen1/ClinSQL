WITH asthma_adms AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 88 AND 98
    AND (
         di.icd_code LIKE '493%'  -- ICD-9 asthma
      OR di.icd_code LIKE 'J45%'  -- ICD-10 asthma
      OR LOWER(COALESCE(dd.long_title, '')) LIKE '%asthma%'
    )
),

adms_proc AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS stay_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE 'other'
    END AS stay_bucket,
    COUNT(DISTINCT CASE WHEN LOWER(COALESCE(dp.long_title, '')) LIKE '%diagnostic%' THEN pi.seq_num END) AS diagnostic_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN asthma_adms AS aa
    ON aa.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
    ON pi.subject_id = a.subject_id AND pi.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
    ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
  GROUP BY a.hadm_id, a.admittime, a.dischtime
)

SELECT
  stay_bucket,
  quantiles[OFFSET(1)] AS p25,
  quantiles[OFFSET(2)] AS p50,
  quantiles[OFFSET(3)] AS p75
FROM (
  SELECT stay_bucket, APPROX_QUANTILES(diagnostic_proc_count, 4) AS quantiles
  FROM adms_proc
  WHERE stay_bucket IN ('1-3 days', '4-7 days')
  GROUP BY stay_bucket
)
ORDER BY stay_bucket;