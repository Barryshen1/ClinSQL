WITH first_icustay AS (
  SELECT subject_id, hadm_id, stay_id, intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) = 1
),
age_filter AS (
  SELECT f.subject_id, f.hadm_id, f.stay_id
  FROM first_icustay f
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = f.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 66 AND 76
),
sepsis_cohort AS (
  SELECT af.subject_id, af.hadm_id, af.stay_id
  FROM age_filter af
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
      ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
    WHERE di.subject_id = af.subject_id
      AND di.hadm_id = af.hadm_id
      AND LOWER(ddi.long_title) LIKE '%sepsis%'
  )
),
no_sepsis_cohort AS (
  SELECT af.subject_id, af.hadm_id, af.stay_id
  FROM age_filter af
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
      ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
    WHERE di.subject_id = af.subject_id
      AND di.hadm_id = af.hadm_id
      AND LOWER(ddi.long_title) LIKE '%sepsis%'
  )
),
all_groups AS (
  SELECT subject_id, hadm_id, stay_id, 'sepsis' AS group_type
  FROM sepsis_cohort
  UNION ALL
  SELECT subject_id, hadm_id, stay_id, 'control' AS group_type
  FROM no_sepsis_cohort
),
per_stay_procs AS (
  SELECT ag.subject_id, ag.hadm_id, ag.stay_id, ag.group_type,
         COUNT(DISTINCT pe.itemid) AS distinct_proc_48h
  FROM all_groups ag
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON i.stay_id = ag.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
     ON pe.stay_id = ag.stay_id
     AND pe.starttime >= i.intime
     AND pe.starttime < TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
  GROUP BY ag.subject_id, ag.hadm_id, ag.stay_id, ag.group_type
),
los AS (
  SELECT ag.subject_id, ag.hadm_id, ag.stay_id, ag.group_type,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los_days,
         a.hospital_expire_flag
  FROM all_groups ag
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.subject_id = ag.subject_id AND a.hadm_id = ag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON i.stay_id = ag.stay_id
),
per_group_stats AS (
  SELECT p.group_type,
         AVG(l.hosp_los_days) AS mean_hosp_los_days,
         AVG(CASE WHEN l.hospital_expire_flag = 1 THEN 1.0 ELSE 0 END) AS in_hospital_mortality_rate
  FROM per_stay_procs p
  JOIN los l
    ON l.subject_id = p.subject_id
   AND l.hadm_id = p.hadm_id
   AND l.stay_id = p.stay_id
  GROUP BY p.group_type
),
p90s AS (
  SELECT p.group_type,
         (SELECT quant[OFFSET(90)]
          FROM UNNEST(APPROX_QUANTILES(p.distinct_proc_48h, 100)) AS quant) AS p90_distinct_procedures_48h
  FROM per_stay_procs p
  GROUP BY p.group_type
)
SELECT s.group_type,
       p90s.p90_distinct_procedures_48h,
       g.mean_hosp_los_days,
       g.in_hospital_mortality_rate
FROM p90s
JOIN per_group_stats g
  ON g.group_type = p90s.group_type
ORDER BY s.group_type;