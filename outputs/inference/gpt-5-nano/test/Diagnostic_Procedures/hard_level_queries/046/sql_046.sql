WITH
-- Define each patient's first ICU stay (earliest intime per subject)
first_icu AS (
  SELECT t.subject_id, t.hadm_id, t.stay_id, t.intime
  FROM (
    SELECT subject_id, hadm_id, stay_id, intime,
           ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) AS t
  WHERE rn = 1
),

-- ARDS during first ICU stay
ARDS_first_icu AS (
  SELECT f.subject_id, f.hadm_id, f.stay_id, f.intime
  FROM first_icu f
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = f.subject_id AND di.hadm_id = f.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%acute respiratory distress syndrome%'
),

-- ARDS group: female and age 37-47
ARDS_female_37_47 AS (
  SELECT a.subject_id, a.hadm_id, a.stay_id, a.intime
  FROM ARDS_first_icu a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 37 AND 47
),

-- All ICU group (first ICU stay)
All_first_icu AS (
  SELECT subject_id, hadm_id, stay_id, intime
  FROM first_icu
),
All_group AS (
  SELECT subject_id, hadm_id, stay_id, intime
  FROM All_first_icu
),

-- Distinct 72-hour procedure counts for ARDS group
ARDS_proc AS (
  SELECT af.subject_id,
         COUNT(DISTINCT pe.itemid) AS dist_proc_count
  FROM ARDS_female_37_47 af
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.subject_id = af.subject_id
   AND pe.hadm_id = af.hadm_id
   AND pe.stay_id = af.stay_id
   AND pe.starttime >= af.intime
   AND pe.starttime < TIMESTAMP_ADD(af.intime, INTERVAL 72 HOUR)
  GROUP BY af.subject_id
),

-- Distinct 72-hour procedure counts for All ICU group
All_proc AS (
  SELECT ag.subject_id,
         COUNT(DISTINCT pe.itemid) AS dist_proc_count
  FROM All_group ag
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.subject_id = ag.subject_id
   AND pe.hadm_id = ag.hadm_id
   AND pe.stay_id = ag.stay_id
   AND pe.starttime >= ag.intime
   AND pe.starttime < TIMESTAMP_ADD(ag.intime, INTERVAL 72 HOUR)
  GROUP BY ag.subject_id
),

-- LOS for ARDS group (per subject admission)
ARDS_los AS (
  SELECT af.subject_id,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM ARDS_female_37_47 af
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = af.hadm_id
),

-- LOS for All ICU group (per subject admission)
All_los AS (
  SELECT ag.subject_id,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM All_group ag
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = ag.hadm_id
),

-- Means for LOS
ARDS_los_mean AS (
  SELECT AVG(los_days) AS los_mean
  FROM ARDS_los
),
All_los_mean AS (
  SELECT AVG(los_days) AS los_mean
  FROM All_los
),

-- Mortality rates (in-hospital)
ARDS_mort AS (
  SELECT AVG(a.hospital_expire_flag) AS mort_rate
  FROM ARDS_female_37_47 af
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = af.hadm_id
),
All_mort AS (
  SELECT AVG(a.hospital_expire_flag) AS mort_rate
  FROM All_group ag
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = ag.hadm_id
),

-- Quantiles for ARDS group
ARDS_quant AS (
  SELECT APPROX_QUANTILES(dist_proc_count, 100) AS q
  FROM ARDS_proc
),

-- Quantiles for All group
All_quant AS (
  SELECT APPROX_QUANTILES(dist_proc_count, 100) AS q
  FROM All_proc
)

-- Final two-group summary rows
SELECT 'ARDS_female_37_47' AS group_name,
       ARDS_quant.q[OFFSET(74)] AS p75,
       ARDS_quant.q[OFFSET(89)] AS p90,
       ARDS_los_mean.los_mean AS mean_los_days,
       ARDS_mort.mort_rate AS in_hospital_mortality
FROM ARDS_quant, ARDS_los_mean, ARDS_mort

UNION ALL

SELECT 'All_ICU_patients' AS group_name,
       All_quant.q[OFFSET(74)] AS p75,
       All_quant.q[OFFSET(89)] AS p90,
       All_los_mean.los_mean AS mean_los_days,
       All_mort.mort_rate AS in_hospital_mortality
FROM All_quant, All_los_mean, All_mort;