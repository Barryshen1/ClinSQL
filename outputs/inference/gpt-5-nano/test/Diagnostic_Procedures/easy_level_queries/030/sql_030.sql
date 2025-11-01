WITH cohort_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
),
echocounts AS (
  SELECT pi.hadm_id,
         COUNT(DISTINCT pi.icd_code) AS cnt_echo
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON pi.icd_code = d.icd_code
   AND pi.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%echo%'
  GROUP BY pi.hadm_id
)
SELECT
  CAST(APPROX_QUANTILES(COALESCE(ec.cnt_echo, 0), 100)[OFFSET(24)] AS FLOAT64) AS p25_distinct_echoes_per_hadm
FROM cohort_admissions ca
LEFT JOIN echocounts ec
  ON ca.hadm_id = ec.hadm_id;