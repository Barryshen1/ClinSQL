WITH dialysis_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON adm.hadm_id = proc.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON proc.icd_code = dicd.icd_code
    AND proc.icd_version = dicd.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 77 AND 87
    AND LOWER(dicd.long_title) LIKE '%dialysis%'
),
first_icu_stays AS (
  SELECT 
    icu.subject_id, 
    icu.los,
    ROW_NUMBER() OVER (
      PARTITION BY icu.subject_id 
      ORDER BY icu.intime
    ) AS stay_rank
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN dialysis_admissions da
    ON icu.subject_id = da.subject_id
    AND icu.hadm_id = da.hadm_id
)
SELECT 
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] - APPROX_QUANTILES(los, 100)[OFFSET(25)] AS iqr
FROM first_icu_stays
WHERE stay_rank = 1;