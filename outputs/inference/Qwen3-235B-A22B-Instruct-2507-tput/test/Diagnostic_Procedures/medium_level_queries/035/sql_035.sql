WITH patients_filtered AS (
  SELECT p.subject_id,
         EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 43 AND 53
),

admissions_with_los AS (
  SELECT a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered pf
    ON a.subject_id = pf.subject_id
  WHERE a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

aki_diagnoses AS (
  SELECT di.hadm_id,
         di.seq_num,
         di.icd_code,
         CASE WHEN di.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS aki_rank
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_version = 10
    AND di.icd_code LIKE 'N17%'
),

admissions_aki_type AS (
  SELECT hadm_id,
         CASE 
           WHEN MIN(seq_num) = 1 AND SUM(CASE WHEN seq_num = 1 THEN 1 ELSE 0 END) > 0 THEN 'primary'
           ELSE 'secondary'
         END AS aki_type
  FROM aki_diagnoses
  GROUP BY hadm_id
),

imaging_events AS (
  SELECT h.hadm_id,
         COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp`.hcpcsevents h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_hcpcs d
    ON h.hcpcs_cd = d.code
  WHERE LOWER(d.short_description) LIKE '%mri%'
     OR LOWER(d.short_description) LIKE '%ct%'
  GROUP BY h.hadm_id
),

combined AS (
  SELECT a.hadm_id,
         a.subject_id,
         a.los_days,
         COALESCE(i.imaging_count, 0) AS imaging_count,
         akt.aki_type
  FROM admissions_with_los a
  INNER JOIN admissions_aki_type akt
    ON a.hadm_id = akt.hadm_id
  LEFT JOIN imaging_events i
    ON a.hadm_id = i.hadm_id
)

SELECT aki_type,
       CASE 
         WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
         WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
       END AS los_group,
       COUNT(DISTINCT subject_id) AS patient_count,
       AVG(imaging_count) AS mean_mri_ct_per_admission
FROM combined
GROUP BY aki_type, los_group
ORDER BY aki_type, los_group;