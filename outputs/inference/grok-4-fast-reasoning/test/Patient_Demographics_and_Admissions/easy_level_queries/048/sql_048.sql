WITH first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
eligible_first_adms AS (
  SELECT 
    *,
    anchor_age + EXTRACT(YEAR FROM admittime) - 2008 AS age_at_adm
  FROM first_admissions
  WHERE rn = 1
    AND anchor_age + EXTRACT(YEAR FROM admittime) - 2008 BETWEEN 79 AND 89
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = first_admissions.subject_id
        AND d.hadm_id = first_admissions.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%') 
          OR 
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
)
SELECT 
  APPROX_QUANTILES(
    DATE_DIFF(dischtime, admittime, DAY), 
    4
  )[OFFSET(3)] 
  - 
  APPROX_QUANTILES(
    DATE_DIFF(dischtime, admittime, DAY), 
    4
  )[OFFSET(1)] AS iqr_los_days
FROM eligible_first_adms;