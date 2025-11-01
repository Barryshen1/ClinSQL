WITH eligible_admissions AS (
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 52 AND 62
),
valve_procedures_per_hadm AS (
  SELECT pi.hadm_id,
         COUNT(DISTINCT CONCAT(pi.icd_code, '|', CAST(pi.chartdate AS STRING), '|', CAST(pi.seq_num AS STRING))) AS valve_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS di
    ON pi.icd_code = di.icd_code
   AND pi.icd_version = di.icd_version
  JOIN eligible_admissions ea ON pi.hadm_id = ea.hadm_id
  WHERE LOWER(di.long_title) LIKE '%valve%'
    AND (LOWER(di.long_title) LIKE '%replacement%' OR LOWER(di.long_title) LIKE '%repair%')
  GROUP BY pi.hadm_id
)
SELECT
  quantiles[OFFSET(1)] AS q1,
  quantiles[OFFSET(3)] AS q3,
  (quantiles[OFFSET(3)] - quantiles[OFFSET(1)]) AS iqr
FROM (
  SELECT APPROX_QUANTILES(valve_proc_count, 4) AS quantiles
  FROM valve_procedures_per_hadm
);