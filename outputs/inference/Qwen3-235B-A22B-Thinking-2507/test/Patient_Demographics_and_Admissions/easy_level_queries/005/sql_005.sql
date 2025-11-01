WITH qualifying_admissions AS (
  SELECT 
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admittance_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 77 AND 87
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p_icd
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
        ON p_icd.icd_code = d.icd_code AND p_icd.icd_version = d.icd_version
      WHERE 
        p_icd.hadm_id = a.hadm_id
        AND LOWER(d.long_title) LIKE '%dialysis%'
    )
),
first_icu_stays AS (
  SELECT 
    i.hadm_id,
    i.los,
    ROW_NUMBER() OVER (
      PARTITION BY i.hadm_id 
      ORDER BY i.intime
    ) AS stay_rank
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN qualifying_admissions qa
    ON i.hadm_id = qa.hadm_id
)
SELECT 
  APPROX_QUANTILES(los, 1000)[OFFSET(750)] - APPROX_QUANTILES(los, 1000)[OFFSET(250)] AS iqr
FROM first_icu_stays
WHERE stay_rank = 1;