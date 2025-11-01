WITH first_admissions AS (
  SELECT 
    a.*,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
cabg_cohort AS (
  SELECT 
    fa.hadm_id,
    fa.age_at_admission
  FROM first_admissions fa
  WHERE 
    fa.rn = 1
    AND fa.gender = 'M'
    AND fa.age_at_admission BETWEEN 48 AND 58
    AND fa.hospital_expire_flag = 1
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON pi.icd_code = d.icd_code 
        AND pi.icd_version = d.icd_version
      WHERE 
        pi.hadm_id = fa.hadm_id
        AND LOWER(d.long_title) LIKE '%coronary artery bypass%'
    )
)
SELECT
  APPROX_QUANTILES(age_at_admission, 1000)[OFFSET(250)] AS percentile_25
FROM cabg_cohort;