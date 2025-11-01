WITH lower_gi_bleed_patients AS (
  -- Identify patients with lower GI bleeding diagnosis
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      -- ICD-10 codes for lower GI bleeding
      REGEXP_CONTAINS(dd.long_title, r'(?i)(lower gastrointestinal|rectal bleeding|hematochezia|anal bleeding|colonic bleeding|gi hemorrhage|gastrointestinal hemorrhage|melena|diverticular bleeding|angiodysplasia|colitis|proctitis|hemorrhoid|anal fissure|ulcer|bleeding|hemorrhage)')
      OR
      -- ICD-9 codes for lower GI bleeding
      d.icd_code IN ('5781','5693','56986','56987','56988','56989','5699','56981','56982','56983','56984','56985')
    )
),
first_icu_stays AS (
  -- Get first ICU stay for each patient
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
),
cohort AS (
  -- Filter for age, gender, lower GI bleed, first ICU stay
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    f.los
  FROM
    first_icu_stays f
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON f.subject_id = p.subject_id
    JOIN lower_gi_bleed_patients lgb
      ON f.subject_id = lgb.subject_id AND f.hadm_id = lgb.hadm_id
  WHERE
    f.rn = 1
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
),
procedure_counts AS (
  -- Count distinct procedures in first 48h of ICU stay
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.los,
    COALESCE(COUNT(DISTINCT pr.icd_code), 0) AS procedure_count
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      ON c.subject_id = pr.subject_id
      AND c.hadm_id = pr.hadm_id
      AND pr.chartdate >= c.intime
      AND pr.chartdate < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id, c.intime, c.outtime, c.los
),
mortality AS (
  -- Get in-hospital mortality
  SELECT
    pc.*,
    a.hospital_expire_flag
  FROM
    procedure_counts pc
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON pc.hadm_id = a.hadm_id
),
quintiles AS (
  -- Assign quintiles based on procedure count
  SELECT
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS procedure_quintile
  FROM
    mortality
)
SELECT
  procedure_quintile,
  COUNT(*) AS n_patients,
  ROUND(AVG(procedure_count),2) AS mean_procedure_count,
  ROUND(AVG(los),2) AS mean_icu_los_days,
  ROUND(100 * AVG(CAST(hospital_expire_flag AS FLOAT64)),2) AS in_hospital_mortality_percent
FROM
  quintiles
GROUP BY
  procedure_quintile
ORDER BY
  procedure_quintile;