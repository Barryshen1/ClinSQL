WITH gi_bleed_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE
      WHEN di.long_title LIKE '%upper gastrointestinal hemorrhage%'
        OR di.long_title LIKE '%gastrointestinal hemorrhage upper%'
        OR di.long_title LIKE '%upper GI bleed%'
        OR di.long_title LIKE '%upper gastrointestinal bleeding%'
        OR di.long_title LIKE '%gastric hemorrhage%'
        OR di.long_title LIKE '%esophageal hemorrhage%'
        OR di.long_title LIKE '%duodenal hemorrhage%'
        OR di.long_title LIKE '%peptic ulcer hemorrhage%'
        OR di.long_title LIKE '%variceal hemorrhage%'
        OR di.long_title LIKE '%hematemesis%'
        OR di.long_title LIKE '%melena%'
        OR (di.long_title LIKE '%hematochezia%' AND di.long_title LIKE '%upper%')
        THEN 'Upper'
      WHEN di.long_title LIKE '%lower gastrointestinal hemorrhage%'
        OR di.long_title LIKE '%gastrointestinal hemorrhage lower%'
        OR di.long_title LIKE '%lower GI bleed%'
        OR di.long_title LIKE '%lower gastrointestinal bleeding%'
        OR di.long_title LIKE '%hematochezia%'
        OR di.long_title LIKE '%colonic hemorrhage%'
        OR di.long_title LIKE '%rectal hemorrhage%'
        OR di.long_title LIKE '%diverticular hemorrhage%'
        OR di.long_title LIKE '%angiodysplasia hemorrhage%'
        THEN 'Lower'
      ELSE NULL
    END AS gi_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_cd
    ON a.hadm_id = di_cd.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON di_cd.icd_code = di.icd_code AND di_cd.icd_version = di.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND (
      di.long_title LIKE '%upper gastrointestinal hemorrhage%'
      OR di.long_title LIKE '%gastrointestinal hemorrhage upper%'
      OR di.long_title LIKE '%upper GI bleed%'
      OR di.long_title LIKE '%upper gastrointestinal bleeding%'
      OR di.long_title LIKE '%gastric hemorrhage%'
      OR di.long_title LIKE '%esophageal hemorrhage%'
      OR di.long_title LIKE '%duodenal hemorrhage%'
      OR di.long_title LIKE '%peptic ulcer hemorrhage%'
      OR di.long_title LIKE '%variceal hemorrhage%'
      OR di.long_title LIKE '%hematemesis%'
      OR di.long_title LIKE '%melena%'
      OR di.long_title LIKE '%hematochezia%'
      OR di.long_title LIKE '%lower gastrointestinal hemorrhage%'
      OR di.long_title LIKE '%gastrointestinal hemorrhage lower%'
      OR di.long_title LIKE '%lower GI bleed%'
      OR di.long_title LIKE '%lower gastrointestinal bleeding%'
      OR di.long_title LIKE '%colonic hemorrhage%'
      OR di.long_title LIKE '%rectal hemorrhage%'
      OR di.long_title LIKE '%diverticular hemorrhage%'
      OR di.long_title LIKE '%angiodysplasia hemorrhage%'
    )
),
admissions_with_icu AS (
  SELECT
    gba.*,
    CASE
      WHEN i.stay_id IS NOT NULL THEN 1
      ELSE 0
    END AS any_icu_admission,
    CASE
      WHEN i.intime >= gba.admittime
        AND i.intime <= TIMESTAMP_ADD(gba.admittime, INTERVAL 24 HOUR)
        THEN 1
      ELSE 0
    END AS day1_icu_status
  FROM gi_bleed_admissions gba
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON gba.hadm_id = i.hadm_id
)
SELECT
  gi_type,
  CASE
    WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 2 THEN '1–2'
    WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 3 AND 5 THEN '3–5'
    WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 6 AND 9 THEN '6–9'
    WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) >= 10 THEN '≥10'
    ELSE 'Unknown'
  END AS los_category,
  day1_icu_status,
  SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS in_hospital_mortality_pct,
  SUM(any_icu_admission) * 100.0 / COUNT(*) AS icu_admission_rate_pct
FROM admissions_with_icu
WHERE gi_type IS NOT NULL
GROUP BY gi_type, los_category, day1_icu_status
ORDER BY gi_type, los_category, day1_icu_status;