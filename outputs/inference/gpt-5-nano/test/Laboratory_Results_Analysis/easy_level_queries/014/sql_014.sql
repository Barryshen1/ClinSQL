WITH qualifying_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'Female'
    AND (CAST(p.anchor_age AS INT64) +
         (EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64))) BETWEEN 44 AND 46
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '578%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'K92%')
    )
),
hem_last_values AS (
  SELECT l.hadm_id,
         l.valuenum,
         l.charttime
  FROM qualifying_admissions qa
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON qa.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.hadm_id = qa.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%hemoglobin%'
    AND l.valuenum IS NOT NULL
    AND l.charttime <= a.dischtime
),
last_per_hadm AS (
  SELECT hadm_id, valuenum,
         ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime DESC) AS rn
  FROM hem_last_values
)
SELECT q[OFFSET(74)] AS p75_discharge_hemoglobin_g_per_dL
FROM (
  SELECT APPROX_QUANTILES(valuenum, 100) AS q
  FROM last_per_hadm
  WHERE rn = 1
) AS t;