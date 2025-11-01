WITH first_icu_stay AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id, 
    intime,  -- Added for age calculation
    los,
    ROW_NUMBER() OVER (
      PARTITION BY subject_id 
      ORDER BY intime
    ) AS stay_order
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE los IS NOT NULL
),
qualified_patients AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los
  FROM first_icu_stay icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year BETWEEN 43 AND 53  -- Fixed parentheses
    AND EXISTS (  -- Avoids duplicate ICU stays
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code 
        AND diag.icd_version = d.icd_version
      WHERE diag.hadm_id = icu.hadm_id
        AND LOWER(d.long_title) LIKE '%pneumonia%'
    )
    AND icu.stay_order = 1  -- First ICU stay only
)
SELECT 
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS percentile_25_los_days
FROM qualified_patients;