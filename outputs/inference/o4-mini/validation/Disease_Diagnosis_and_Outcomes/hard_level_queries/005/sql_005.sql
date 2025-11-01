WITH
-- 1) Base female patients aged 43-53
fem43_53 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 43 AND 53
),

-- 2) All heart failure ICU stays for that group
hf_icu AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    p.dod,
    ic.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON ic.subject_id = adm.subject_id
     AND ic.hadm_id    = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON ic.subject_id = p.subject_id
    JOIN fem43_53 f
      ON ic.subject_id = f.subject_id
    -- require a heart failure diagnosis on this admission
    JOIN (
      SELECT DISTINCT
        subject_id,
        hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
          ON d.icd_code    = dd.icd_code
         AND d.icd_version = dd.icd_version
      WHERE
        LOWER(dd.long_title) LIKE '%heart failure%'
    ) hf
      ON ic.subject_id = hf.subject_id
     AND ic.hadm_id    = hf.hadm_id
),

-- 3) Attach mortality and complication flags
cohort AS (
  SELECT
    h.*,
    -- 30-day mortality flag
    CASE
      WHEN h.dod IS NOT NULL
       AND DATE_DIFF(DATE(h.dod), DATE(h.admittime), DAY) <= 30 THEN 1
      ELSE 0
    END AS death30_flag,
    -- major complication flag (placeholder list)
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
        WHERE d2.subject_id = h.subject_id
          AND d2.hadm_id    = h.hadm_id
          AND d2.icd_code IN ('9972','99592' /* etc */)
      ) THEN 1
      ELSE 0
    END AS comp_flag
  FROM
    hf_icu h
),

-- 4) Cohort summary metrics
cohort_metrics AS (
  SELECT
    COUNT(*) AS n_patients,
    AVG(death30_flag) AS mortality_30d_rate,
    AVG(comp_flag)    AS major_comp_rate,
    AVG(CASE WHEN death30_flag = 0 THEN los END) AS avg_los_survivors
  FROM
    cohort
)

-- Final output
SELECT
  n_patients,
  mortality_30d_rate,
  major_comp_rate,
  avg_los_survivors
FROM
  cohort_metrics;