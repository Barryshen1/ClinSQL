with Hyperosmolar Hyperglycemic State
WITH targeted_icu AS (
  SELECT i.stay_id, i.hadm_id, i.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = i.subject_id AND di.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 66 AND 76
    AND LOWER(dd.long_title) LIKE '%hyperosmolar%'
),

-- 2) Compute 48-hour procedure burden per ICU stay
icu_proc AS (
  SELECT t.stay_id, t.hadm_id, t.subject_id,
         SUM(CASE WHEN pe.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
                  THEN 1 ELSE 0 END) AS proc48
  FROM targeted_icu AS t
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON i.stay_id = t.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON pe.stay_id = t.stay_id
  GROUP BY t.stay_id, t.hadm_id, t.subject_id
),

-- 3) Prepare hospital admission-level info: mortality, LOS, and 30-day readmission flag
adm_base AS (
  SELECT a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime,
         CASE WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS hosp_death,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS hosp_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
),

adm_with_next AS (
  SELECT a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime,
         a.hosp_death,
         a.hosp_los_days,
         LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
  FROM adm_base AS a
),

adm_readmit AS (
  SELECT hadm_id,
         subject_id,
         admittime,
         dischtime,
         hosp_death,
         hosp_los_days,
         CASE WHEN next_admittime IS NOT NULL
                   AND next_admittime <= TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY)
              THEN 1 ELSE 0 END AS readmit_30
  FROM adm_with_next
)

SELECT quint,
       COUNT(*) AS num_stays,
       AVG(proc48) AS mean_procedures,
       MIN(proc48) AS min_proc,
       MAX(proc48) AS max_proc,
       AVG(CASE WHEN hosp_death = 1 THEN 1.0 ELSE 0.0 END) * 100 AS hospital_mortality_pct,
       AVG(hosp_los_days) AS mean_hosp_los_days,
       AVG(readmit_30) * 100 AS readmit_30_pct
FROM (
  SELECT
    p.stay_id,
    p.hadm_id,
    p.subject_id,
    p.proc48,
    r.hosp_death,
    r.hosp_los_days,
    r.readmit_30,
    NTILE(5) OVER (ORDER BY p.proc48) AS quint
  FROM icu_proc AS p
  JOIN targeted_icu AS t ON t.stay_id = p.stay_id
  JOIN adm_readmit AS r ON r.hadm_id = p.hadm_id
) AS with_quint
GROUP BY quint
ORDER BY quint;