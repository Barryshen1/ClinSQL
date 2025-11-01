WITH female_medicare_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.anchor_year,
    a.insurance,
    a.admission_location,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY DEPARTMENT'
    AND a.dischtime IS NOT NULL
),

bowel_obstruction_diagnoses AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.seq_num,
    di.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    (d.icd_code LIKE 'K56.%' OR d.icd_code LIKE '560.%')
    AND d.seq_num = 1  -- Principal diagnosis
)

SELECT
  COUNT(DISTINCT fmp.hadm_id) AS completed_index_admissions
FROM
  female_medicare_patients fmp
JOIN
  bowel_obstruction_diagnoses bod
ON
  fmp.subject_id = bod.subject_id
  AND fmp.hadm_id = bod.hadm_id
WHERE
  -- Calculate age at admission (anchor_age + (admission_year - anchor_year))
  (fmp.anchor_age + (EXTRACT(YEAR FROM fmp.admittime) - fmp.anchor_year)) BETWEEN 43 AND 53;