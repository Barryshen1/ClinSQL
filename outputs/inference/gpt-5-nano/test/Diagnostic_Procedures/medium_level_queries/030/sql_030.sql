WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE LOWER(gender) IN ('f', 'female')
    AND anchor_age BETWEEN 53 AND 63
),

ugib_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients ep ON ep.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
  WHERE (
        LOWER(dd.long_title) LIKE '%upper%' AND LOWER(dd.long_title) LIKE '%hemorrhage%'
      )
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 8
),

admission_bins AS (
  SELECT a.subject_id, a.hadm_id,
         CASE
           WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 4 THEN '1-4'
           WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 5 AND 8 THEN '5-8'
         END AS stay_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.hadm_id IN (SELECT hadm_id FROM ugib_admissions)
),

per_admission AS (
  SELECT ib.hadm_id, ib.stay_group,
         SUM(CASE WHEN dp.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS diag_proc_cnt
  FROM admission_bins ib
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pc
    ON pc.hadm_id = ib.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON dp.icd_code = pc.icd_code AND dp.icd_version = pc.icd_version
  GROUP BY ib.hadm_id, ib.stay_group
),

quartiles AS (
  SELECT stay_group,
         APPROX_QUANTILES(diag_proc_cnt, 4) AS q
  FROM per_admission
  GROUP BY stay_group
)

SELECT
  stay_group,
  CAST(q[OFFSET(1)] AS INT64) AS p25,  -- 25th percentile
  CAST(q[OFFSET(2)] AS INT64) AS p50,  -- 50th percentile (median)
  CAST(q[OFFSET(3)] AS INT64) AS p75   -- 75th percentile
FROM quartiles
ORDER BY stay_group;