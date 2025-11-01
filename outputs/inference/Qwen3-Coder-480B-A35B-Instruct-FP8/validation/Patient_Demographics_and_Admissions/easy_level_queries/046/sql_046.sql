WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_rank
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
),
dapt_admissions AS (
  SELECT DISTINCT
    p.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions p
  WHERE
    LOWER(p.drug) IN ('clopidogrel', 'ticagrelor', 'prasugrel', 'aspirin')
    AND p.drug_type = 'MAIN'
),
filtered_patients AS (
  SELECT
    fa.hadm_id,
    fa.hospital_expire_flag
  FROM
    first_admissions fa
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pt
    ON fa.subject_id = pt.subject_id
  JOIN
    dapt_admissions da
    ON fa.hadm_id = da.hadm_id
  WHERE
    fa.admission_rank = 1
    AND pt.gender = 'M'
    AND pt.anchor_age BETWEEN 37 AND 47
)
SELECT
  STDDEV_SAMP(hospital_expire_flag) AS stddev_mortality
FROM
  filtered_patients;