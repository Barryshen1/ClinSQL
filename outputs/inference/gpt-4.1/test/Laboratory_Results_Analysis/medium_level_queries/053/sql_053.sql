WITH female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 68 AND 78
),
acs_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  WHERE adm.subject_id IN (SELECT subject_id FROM female_patients)
    AND (
      -- ICD-9 ACS codes
      (dx.icd_version = 9 AND (
        LEFT(dx.icd_code,3) IN ('410','411','412','413','414')
      ))
      OR
      -- ICD-10 ACS codes
      (dx.icd_version = 10 AND (
        LEFT(dx.icd_code,3) IN ('I20','I21','I22','I23','I24','I25')
      ))
    )
),
troponin_labs AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE LOWER(dli.label) LIKE '%troponin i%'
    AND le.valuenum IS NOT NULL
),
first_trop AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- First Troponin I charttime per admission
    ARRAY_AGG(tl ORDER BY tl.charttime ASC LIMIT 1)[OFFSET(0)].charttime AS first_charttime,
    ARRAY_AGG(tl ORDER BY tl.charttime ASC LIMIT 1)[OFFSET(0)].valuenum AS first_trop_value,
    ARRAY_AGG(tl ORDER BY tl.charttime ASC LIMIT 1)[OFFSET(0)].valueuom AS first_trop_unit
  FROM acs_admissions a
  JOIN troponin_labs tl
    ON a.subject_id = tl.subject_id AND a.hadm_id = tl.hadm_id
  GROUP BY a.subject_id, a.hadm_id
)
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  ROUND(AVG(first_trop_value),3) AS mean_troponin_I,
  ROUND(STDDEV(first_trop_value),3) AS sd_troponin_I,
  ROUND(MIN(first_trop_value),3) AS min_troponin_I,
  ROUND(MAX(first_trop_value),3) AS max_troponin_I
FROM first_trop
WHERE first_trop_value > 0.04
  AND (first_trop_unit = 'ng/mL' OR first_trop_unit IS NULL);