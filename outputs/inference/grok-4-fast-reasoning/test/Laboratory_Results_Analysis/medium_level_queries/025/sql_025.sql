WITH qualifying_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 58 AND 68
),
qualifying_admissions AS (
  SELECT subject_id, hadm_id
  FROM (
    SELECT
      di.subject_id,
      di.hadm_id,
      a.admittime,
      ROW_NUMBER() OVER (
        PARTITION BY di.subject_id
        ORDER BY a.admittime ASC
      ) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON di.hadm_id = a.hadm_id
    INNER JOIN qualifying_patients qp
      ON di.subject_id = qp.subject_id
    WHERE (
      (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code = '7865'))
      OR
      (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'R07%'))
    )
  ) ranked
  WHERE rn = 1
),
troponin_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_troponins AS (
  SELECT hadm_id, valuenum
  FROM (
    SELECT
      le.hadm_id,
      le.valuenum,
      le.charttime,
      le.storetime,
      ROW_NUMBER() OVER (
        PARTITION BY le.hadm_id
        ORDER BY le.charttime ASC, le.storetime ASC
      ) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN qualifying_admissions qa
      ON le.hadm_id = qa.hadm_id
    INNER JOIN troponin_item ti
      ON le.itemid = ti.itemid
    WHERE le.valueuom = 'ng/mL'
      AND le.valuenum IS NOT NULL
  ) ranked
  WHERE rn = 1
    AND valuenum > 0.01
)
SELECT
  COUNT(*) AS n_patients,
  AVG(valuenum) AS mean_troponin_t,
  STDDEV_SAMP(valuenum) AS sd_troponin_t,
  MIN(valuenum) AS min_troponin_t,
  MAX(valuenum) AS max_troponin_t
FROM first_troponins;