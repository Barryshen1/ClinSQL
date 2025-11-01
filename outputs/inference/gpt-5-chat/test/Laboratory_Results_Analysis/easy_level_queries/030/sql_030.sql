WITH acs_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.subject_id = dx.subject_id
   AND adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age = 57
    AND (
         -- ICD-9 ACS
         (dx.icd_version = 9 AND (
            dx.icd_code LIKE '410%' OR  -- acute MI
            dx.icd_code = '4111'       -- unstable angina/intermediate coronary syndrome
         ))
         OR
         -- ICD-10 ACS
         (dx.icd_version = 10 AND (
            dx.icd_code LIKE 'I20.0%' OR   -- unstable angina
            dx.icd_code LIKE 'I21%'   OR   -- acute MI
            dx.icd_code LIKE 'I22%'        -- subsequent MI
         ))
    )
),
troponin_labs AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON le.itemid = di.itemid
  WHERE di.fluid = 'BLOOD'
    AND LOWER(di.label) LIKE '%troponin%'
    AND le.valuenum IS NOT NULL
)
SELECT a.subject_id,
       a.hadm_id,
       MIN(t.valuenum) AS min_troponin
FROM acs_admissions AS a
JOIN troponin_labs AS t
  ON a.subject_id = t.subject_id
 AND a.hadm_id = t.hadm_id
 AND t.charttime BETWEEN a.admittime AND a.dischtime
GROUP BY a.subject_id, a.hadm_id
ORDER BY min_troponin;