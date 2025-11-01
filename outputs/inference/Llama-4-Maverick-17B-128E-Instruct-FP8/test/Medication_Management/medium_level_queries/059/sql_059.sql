WITH patients_cohort AS (
  SELECT p.subject_id, p.anchor_year, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 60 AND 70
),
t2dm_hf_patients AS (
  SELECT DISTINCT d.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Type 2 diabetes mellitus%' OR dicd.long_title LIKE '%Heart failure%'
),
cohort AS (
  SELECT pc.subject_id
  FROM patients_cohort pc
  JOIN t2dm_hf_patients thp ON pc.subject_id = thp.subject_id
),
icu_stays AS (
  SELECT c.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.subject_id = i.subject_id
),
medications AS (
  SELECT i.subject_id, i.stay_id, p.starttime, p.drug
  FROM icu_stays i
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON i.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN i.intime AND i.outtime
  AND p.drug IN ('list_of_antidiabetics', 'list_of_beta_blockers', 'list_of_acei_arb_arni', 'list_of_loop_diuretics')
),
medication_initiation AS (
  SELECT m.subject_id, m.stay_id,
         COUNT(CASE WHEN m.starttime <= TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR) THEN 1 END) AS init_first_48h,
         COUNT(CASE WHEN m.starttime >= TIMESTAMP_SUB(i.outtime, INTERVAL 24 HOUR) THEN 1 END) AS init_last_24h,
         m.drug
  FROM medications m
  JOIN icu_stays i ON m.stay_id = i.stay_id
  GROUP BY m.subject_id, m.stay_id, m.drug
)
SELECT drug,
       COUNT(CASE WHEN init_first_48h > 0 THEN 1 END) / COUNT(*) * 100 AS init_pct_first_48h,
       COUNT(CASE WHEN init_last_24h > 0 THEN 1 END) / COUNT(*) * 100 AS init_pct_last_24h,
       (COUNT(CASE WHEN init_last_24h > 0 THEN 1 END) / COUNT(*) * 100) - 
       (COUNT(CASE WHEN init_first_48h > 0 THEN 1 END) / COUNT(*) * 100) AS abs_diff_pp
FROM medication_initiation
GROUP BY drug;