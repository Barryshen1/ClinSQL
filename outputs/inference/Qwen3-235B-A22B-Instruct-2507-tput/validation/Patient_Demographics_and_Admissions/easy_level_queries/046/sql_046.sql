WITH first_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag
  FROM (
    SELECT 
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      hospital_expire_flag,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ) ranked
  WHERE rn = 1
),
patients_filtered AS (
  SELECT p.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN first_admissions fa ON p.subject_id = fa.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age >= 37
    AND p.anchor_age <= 47
),
drug_exposure AS (
  SELECT 
    rx.subject_id,
    rx.hadm_id,
    rx.drug,
    rx.starttime,
    COALESCE(rx.stoptime, a.dischtime) AS endtime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
  INNER JOIN first_admissions a ON rx.hadm_id = a.hadm_id
  WHERE LOWER(rx.drug) LIKE '%aspirin%'
     OR LOWER(rx.drug) IN ('clopidogrel', 'ticagrelor', 'prasugrel')
),
aspirin_exposure AS (
  SELECT subject_id, hadm_id, starttime, endtime
  FROM drug_exposure
  WHERE LOWER(drug) LIKE '%aspirin%'
),
p2y12_exposure AS (
  SELECT subject_id, hadm_id, starttime, endtime
  FROM drug_exposure
  WHERE LOWER(drug) IN ('clopidogrel', 'ticagrelor', 'prasugrel')
),
dapt_cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM aspirin_exposure a
  INNER JOIN p2y12_exposure p
    ON a.subject_id = p.subject_id 
   AND a.hadm_id = p.hadm_id
   AND a.starttime < COALESCE(p.endtime, '9999-12-31')
   AND COALESCE(a.endtime, '9999-12-31') > p.starttime
),
cohort_mortality AS (
  SELECT 
    fa.hospital_expire_flag
  FROM dapt_cohort dc
  INNER JOIN first_admissions fa ON dc.hadm_id = fa.hadm_id
  INNER JOIN patients_filtered pf ON dc.subject_id = pf.subject_id
)
SELECT 
  STDDEV(hospital_expire_flag) AS mortality_sd
FROM cohort_mortality;