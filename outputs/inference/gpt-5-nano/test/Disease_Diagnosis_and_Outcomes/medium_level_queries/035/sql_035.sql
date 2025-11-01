WITH
  base AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      a.deathtime,
      p.gender,
      p.anchor_age,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 69 AND 79
      -- Exclude records without discharge time
      AND a.dischtime IS NOT NULL
  ),
  bleed AS (
    SELECT
      b.subject_id,
      b.hadm_id,
      b.admittime,
      b.dischtime,
      b.hospital_expire_flag,
      b.deathtime,
      CASE
        WHEN LOWER(dd.long_title) LIKE '%hematemesis%' OR
             LOWER(dd.long_title) LIKE '%melena%' OR
             LOWER(dd.long_title) LIKE '%gastric%' OR
             LOWER(dd.long_title) LIKE '%duodenal%' OR
             LOWER(dd.long_title) LIKE '%esophageal%' OR
             LOWER(dd.long_title) LIKE '%upper%' THEN 'Upper'
        WHEN LOWER(dd.long_title) LIKE '%hematochezia%' OR
             LOWER(dd.long_title) LIKE '%lower%' OR
             LOWER(dd.long_title) LIKE '%rectal%' OR
             LOWER(dd.long_title) LIKE '%colorectal%' THEN 'Lower'
        ELSE NULL
      END AS bleed_site,
      b.los_days
    FROM base AS b
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON di.subject_id = b.subject_id AND di.hadm_id = b.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE
      (LOWER(dd.long_title) LIKE '%hematemesis%' OR
       LOWER(dd.long_title) LIKE '%melena%' OR
       LOWER(dd.long_title) LIKE '%gastric%' OR
       LOWER(dd.long_title) LIKE '%duodenal%' OR
       LOWER(dd.long_title) LIKE '%esophageal%' OR
       LOWER(dd.long_title) LIKE '%upper%' OR
       LOWER(dd.long_title) LIKE '%hematochezia%' OR
       LOWER(dd.long_title) LIKE '%lower%' OR
       LOWER(dd.long_title) LIKE '%rectal%' OR
       LOWER(dd.long_title) LIKE '%colorectal%' OR
       LOWER(dd.long_title) LIKE '%gastrointestinal hemorrhage%' OR
       LOWER(dd.long_title) LIKE '%g.i. hemorrhage%')
      AND (CASE
             WHEN LOWER(dd.long_title) LIKE '%hematemesis%' OR LOWER(dd.long_title) LIKE '%melena%' OR
                  LOWER(dd.long_title) LIKE '%gastric%' OR LOWER(dd.long_title) LIKE '%duodenal%' OR
                  LOWER(dd.long_title) LIKE '%esophageal%' OR LOWER(dd.long_title) LIKE '%upper%' THEN 'Upper'
             WHEN LOWER(dd.long_title) LIKE '%hematochezia%' OR LOWER(dd.long_title) LIKE '%lower%' OR
                  LOWER(dd.long_title) LIKE '%rectal%' OR LOWER(dd.long_title) LIKE '%colorectal%' THEN 'Lower'
             ELSE NULL
           END) IS NOT NULL
  ),
  flags AS (
    -- Compute ICU flags (per admission) using EXISTS subqueries to avoid duplicates
    SELECT
      bl.subject_id,
      bl.hadm_id,
      bl.admittime,
      bl.dischtime,
      bl.hospital_expire_flag,
      bl.deathtime,
      bl.bleed_site,
      bl.los_days,
      -- ICU present during hospitalization (any ICU stay for this admission)
      CASE WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        WHERE icu.subject_id = bl.subject_id
          AND icu.hadm_id = bl.hadm_id
      ) THEN 1 ELSE 0 END AS icu_any,
      -- Day-1 ICU status: any ICU stay overlapping with the first hospital day
      CASE WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        WHERE icu.subject_id = bl.subject_id
          AND icu.hadm_id = bl.hadm_id
          AND icu.intime <= TIMESTAMP_ADD(bl.admittime, INTERVAL 1 DAY)
          AND icu.outtime > bl.admittime
      ) THEN 1 ELSE 0 END AS day1_icu_status
    FROM bleed AS bl
  ),
  final AS (
    SELECT
      f.subject_id,
      f.hadm_id,
      f.admittime,
      f.dischtime,
      f.hospital_expire_flag,
      f.deathtime,
      f.bleed_site,
      f.los_days,
      CASE
        WHEN f.los_days BETWEEN 1 AND 2 THEN '1-2'
        WHEN f.los_days BETWEEN 3 AND 5 THEN '3-5'
        WHEN f.los_days BETWEEN 6 AND 9 THEN '6-9'
        WHEN f.los_days >= 10 THEN '>=10'
        ELSE 'unknown'
      END AS los_group,
      ff.day1_icu_status AS day1_icu_status,
      ff.icu_any AS icu_any,
      CASE WHEN (f.hospital_expire_flag = 1) OR (f.deathtime IS NOT NULL) THEN 1 ELSE 0 END AS hosp_death
    FROM flags AS ff
    JOIN bleed AS f
      ON ff.subject_id = f.subject_id
     AND ff.hadm_id = f.hadm_id
  )
SELECT
  final.bleed_site AS bleed_site,
  final.los_group AS los_group,
  final.day1_icu_status AS day1_icu_status,
  COUNT(*) AS n_admissions,
  SUM(final.hosp_death) AS deaths,
  SAFE_DIVIDE(SUM(final.hosp_death), COUNT(*)) * 100 AS mortality_percent,
  SAFE_DIVIDE(SUM(final.icu_any), COUNT(*)) * 100 AS icu_admission_rate
FROM final
WHERE final.bleed_site IS NOT NULL
GROUP BY bleed_site, los_group, day1_icu_status
ORDER BY bleed_site, los_group, day1_icu_status;