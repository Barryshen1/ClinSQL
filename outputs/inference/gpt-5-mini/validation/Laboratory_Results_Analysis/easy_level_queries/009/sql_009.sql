WITH acs_admissions AS (
  -- distinct hospital admissions for female patients with an ACS-related diagnosis
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    USING(subject_id, hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    USING(icd_code, icd_version)
  WHERE p.gender = 'F'
    AND REGEXP_CONTAINS(LOWER(icd.long_title),
         r'myocardial infarction|acute coronary|unstable angina')
),

troponin_nadirs AS (
  -- per admission nadir troponin (minimum numeric troponin during the admission)
  SELECT
    a.hadm_id,
    MIN(le.valuenum) AS nadir_troponin
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    USING(itemid)
  JOIN acs_admissions a
    USING(subject_id, hadm_id)
  WHERE REGEXP_CONTAINS(LOWER(di.label), r'troponin')
    AND le.valuenum IS NOT NULL
    -- ensure the lab falls within the admission window
    AND le.charttime BETWEEN a.admittime AND a.dischtime
  GROUP BY a.hadm_id
)

-- 25th percentile of the per-admission nadir troponins (approximate) plus count
SELECT
  (SELECT (APPROX_QUANTILES(nadir_troponin, 100))[OFFSET(25)]
   FROM troponin_nadirs) AS nadir_troponin_p25,
  COUNT(*) AS num_admissions_used
FROM troponin_nadirs;