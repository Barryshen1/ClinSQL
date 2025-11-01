WITH acs_icd_codes AS (
  -- List of ACS ICD codes (ICD-9 and ICD-10)
  SELECT '410' AS icd_code, 9 AS icd_version UNION ALL -- MI
  SELECT '4111', 9 UNION ALL -- Unstable angina
  SELECT 'I21', 10 UNION ALL -- MI
  SELECT 'I22', 10 UNION ALL -- Subsequent MI
  SELECT 'I200', 10         -- Unstable angina
),
acs_admissions AS (
  -- Admissions with ACS diagnosis
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions adm
    JOIN physionet-data.mimiciv_3_1_hosp.patients pat
      ON adm.subject_id = pat.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
      ON adm.hadm_id = dx.hadm_id
    JOIN acs_icd_codes acs
      ON dx.icd_version = acs.icd_version
         AND (LEFT(dx.icd_code, LENGTH(acs.icd_code)) = acs.icd_code)
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age = 64
),
troponin_itemids AS (
  -- Troponin lab itemids
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) LIKE '%troponin%'
    AND category = 'Chemistry'
),
peak_troponin_per_admission AS (
  -- For each ACS admission, get peak troponin value
  SELECT
    a.subject_id,
    a.hadm_id,
    MAX(l.valuenum) AS peak_troponin
  FROM
    acs_admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.labevents l
      ON a.subject_id = l.subject_id
      AND a.hadm_id = l.hadm_id
    JOIN troponin_itemids t
      ON l.itemid = t.itemid
  WHERE
    l.valuenum IS NOT NULL
  GROUP BY
    a.subject_id, a.hadm_id
)
SELECT
  APPROX_QUANTILES(peak_troponin, 4)[OFFSET(3)] AS troponin_75th_percentile
FROM
  peak_troponin_per_admission
;