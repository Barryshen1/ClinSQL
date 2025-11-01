WITH chest_pain_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON diag.icd_code = dicd.icd_code
      AND diag.icd_version = dicd.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 64 AND 74
    AND (
      -- ICD-10 codes for chest pain
      (diag.icd_version = 10 AND diag.icd_code IN ('R07.1', 'R07.2', 'R07.3', 'R07.4'))
      -- ICD-9 code for chest pain (786.50, 786.51, 786.52, 786.59)
      OR (diag.icd_version = 9 AND diag.icd_code IN ('78650', '78651', '78652', '78659'))
    )
),
troponin_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND (LOWER(label) LIKE '%hs%' OR LOWER(label) LIKE '%high sensitivity%')
),
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN troponin_itemids t
      ON l.itemid = t.itemid
  WHERE
    l.valuenum IS NOT NULL
)
-- Main query: join chest pain admissions to first troponin, filter for >99th percentile
SELECT
  COUNT(*) AS num_patients,
  ROUND(AVG(ft.valuenum),2) AS mean_first_troponin,
  ROUND(MIN(ft.valuenum),2) AS min_first_troponin,
  ROUND(MAX(ft.valuenum),2) AS max_first_troponin,
  ROUND(APPROX_QUANTILES(ft.valuenum, 2)[OFFSET(1)],2) AS median_first_troponin,
  ROUND(SUM(CASE WHEN cpa.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 4) AS in_hospital_mortality_rate
FROM
  chest_pain_admissions cpa
  JOIN first_troponin ft
    ON cpa.subject_id = ft.subject_id AND cpa.hadm_id = ft.hadm_id
WHERE
  ft.rn = 1
  -- 99th percentile cutoff: 14 ng/L (adjust if units differ)
  AND (
    (LOWER(ft.valueuom) = 'ng/l' AND ft.valuenum > 14)
    OR (LOWER(ft.valueuom) = 'ng/ml' AND ft.valuenum > 0.014)
    -- Add other unit conversions if needed
  );