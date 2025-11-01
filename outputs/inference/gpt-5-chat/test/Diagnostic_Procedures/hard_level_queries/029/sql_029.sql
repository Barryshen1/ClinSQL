WITH male_age_cohort AS (
  SELECT p.subject_id, p.gender, p.anchor_age,
         i.stay_id, i.hadm_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),
vasopressor_label AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%norepinephrine%'
     OR LOWER(label) LIKE '%epinephrine%'
     OR LOWER(label) LIKE '%phenylephrine%'
     OR LOWER(label) LIKE '%dopamine%'
     OR LOWER(label) LIKE '%vasopressin%'
),
vaso_cohort AS (
  SELECT DISTINCT m.subject_id, m.hadm_id, m.stay_id, m.intime, m.outtime
  FROM male_age_cohort m
  JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON m.stay_id = ie.stay_id
  WHERE ie.itemid IN (SELECT itemid FROM vasopressor_label)
    AND ie.starttime BETWEEN m.intime AND DATETIME_ADD(m.intime, INTERVAL 72 HOUR)
),
labs_72h AS (
  SELECT v.stay_id,
         COUNT(*) AS lab_count
  FROM vaso_cohort v
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON v.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN v.intime AND DATETIME_ADD(v.intime, INTERVAL 72 HOUR)
  GROUP BY v.stay_id
),
imaging_label AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(category) LIKE '%imaging%'
     OR LOWER(label) LIKE '%xray%'
     OR LOWER(label) LIKE '%ct%'
     OR LOWER(label) LIKE '%mri%'
),
imaging_72h AS (
  SELECT v.stay_id,
         COUNT(*) AS img_count
  FROM vaso_cohort v
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON v.stay_id = pe.stay_id
  WHERE pe.itemid IN (SELECT itemid FROM imaging_label)
    AND pe.starttime BETWEEN v.intime AND DATETIME_ADD(v.intime, INTERVAL 72 HOUR)
  GROUP BY v.stay_id
),
diagnostic_load AS (
  SELECT v.subject_id, v.hadm_id, v.stay_id, v.intime,
         COALESCE(l.lab_count,0) + COALESCE(i.img_count,0) AS diag_count
  FROM vaso_cohort v
  LEFT JOIN labs_72h l USING (stay_id)
  LEFT JOIN imaging_72h i USING (stay_id)
),
quartiles AS (
  SELECT d.*,
         NTILE(4) OVER (ORDER BY diag_count) AS quartile
  FROM diagnostic_load d
),
admit_data AS (
  SELECT hadm_id, subject_id, admittime, dischtime, hospital_expire_flag,
         DATETIME_DIFF(dischtime, admittime, DAY) AS hosp_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
-- find 30-day readmissions
next_admit AS (
  SELECT a1.hadm_id,
         CASE WHEN MIN(a2.admittime) IS NOT NULL THEN 1 ELSE 0 END AS readmit_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
   AND a2.admittime > a1.dischtime
   AND DATETIME_DIFF(a2.admittime, a1.dischtime, DAY) <= 30
  GROUP BY a1.hadm_id
)
SELECT q.quartile,
       AVG(q.diag_count) AS avg_diag_count,
       AVG(a.hosp_los) AS avg_hosp_los_days,
       AVG(a.hospital_expire_flag) AS mortality_rate,
       AVG(n.readmit_30d) AS readmit_30d_rate
FROM quartiles q
JOIN admit_data a
  ON q.hadm_id = a.hadm_id
JOIN next_admit n
  ON q.hadm_id = n.hadm_id
GROUP BY q.quartile
ORDER BY q.quartile;