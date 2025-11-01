WITH
-- Identify admissions with an Intracranial Hemorrhage (ICH) diagnosis
ich_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE (
        LOWER(COALESCE(dicd.long_title, '')) LIKE '%intracranial hemorrhage%'
     OR (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) = 'I61')  -- ICD-10 I61*
     OR (d.icd_version = 9  AND d.icd_code = '431')                -- ICD-9 431 (intracerebral hemorrhage)
  )
),

-- ICU stays for the target cohort: female, age 56-66, and admission had ICH
cohort_icustays AS (
  SELECT icu.*
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  JOIN ich_admissions ia
    ON icu.hadm_id = ia.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 56 AND 66
),

-- Aggregate diagnostic event counts within first 72 hours for all icustays
lab_counts AS (
  SELECT icu.stay_id,
         COUNT(l.labevent_id) AS lab_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.subject_id = icu.subject_id
   AND l.hadm_id = icu.hadm_id
   AND DATETIME(l.charttime) BETWEEN DATETIME(icu.intime) AND DATETIME(TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR))
  GROUP BY icu.stay_id
),

micro_counts AS (
  SELECT icu.stay_id,
         COUNT(m.microevent_id) AS micro_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` m
    ON m.subject_id = icu.subject_id
   AND m.hadm_id = icu.hadm_id
   AND DATETIME(m.charttime) BETWEEN DATETIME(icu.intime) AND DATETIME(TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR))
  GROUP BY icu.stay_id
),

hcpcs_counts AS (
  SELECT icu.stay_id,
         COUNT(*) AS hcpcs_count
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
    ON hc.subject_id = icu.subject_id
   AND hc.hadm_id = icu.hadm_id
   AND DATETIME(hc.chartdate) BETWEEN DATETIME(icu.intime) AND DATETIME(TIMESTAMP_ADD(icu.intime, INTERVAL 72 HOUR))
  GROUP BY icu.stay_id
),

-- Per-ICU-stay diagnostic intensity (sum of lab + micro + hcpcs) for all stays
diag_per_stay AS (
  SELECT icu.stay_id,
         COALESCE(lc.lab_count, 0) AS lab_count,
         COALESCE(mc.micro_count, 0) AS micro_count,
         COALESCE(hcpc.hcpcs_count, 0) AS hcpcs_count,
         COALESCE(lc.lab_count, 0) + COALESCE(mc.micro_count, 0) + COALESCE(hcpc.hcpcs_count, 0) AS diag_intensity
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  LEFT JOIN lab_counts lc ON icu.stay_id = lc.stay_id
  LEFT JOIN micro_counts mc ON icu.stay_id = mc.stay_id
  LEFT JOIN hcpcs_counts hcpc ON icu.stay_id = hcpc.stay_id
),

-- Diagnostic intensity restricted to the cohort icustays
cohort_diag AS (
  SELECT dps.*
  FROM diag_per_stay dps
  JOIN cohort_icustays c ON dps.stay_id = c.stay_id
),

-- Cohort summary: 95th percentile diagnostic intensity, median ICU LOS, and in-hospital mortality
cohort_stats AS (
  SELECT
    COUNT(DISTINCT c.stay_id) AS cohort_icustay_count,
    -- 95th percentile of diagnostic intensity
    (APPROX_QUANTILES(c.diag_intensity, 100))[OFFSET(95)] AS diag_intensity_p95,
    -- median ICU LOS for cohort
    (APPROX_QUANTILES(icu.los, 100))[OFFSET(50)] AS median_icu_los_days,
    -- in-hospital mortality for cohort (admissions.hospital_expire_flag)
    SUM(a.hospital_expire_flag) * 1.0 / COUNT(DISTINCT c.stay_id) AS hospital_mortality_rate
  FROM cohort_diag c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON c.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON icu.hadm_id = a.hadm_id
  GROUP BY 1
),

-- Overall ICU population stats (all icustays)
overall_stats AS (
  SELECT
    COUNT(DISTINCT icu.stay_id) AS overall_icustay_count,
    (APPROX_QUANTILES(icu.los, 100))[OFFSET(50)] AS overall_median_icu_los_days,
    SUM(a.hospital_expire_flag) * 1.0 / COUNT(DISTINCT icu.stay_id) AS overall_hospital_mortality_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
)

-- Final select: show cohort 95th percentile and comparison metrics
SELECT
  cs.cohort_icustay_count,
  cs.diag_intensity_p95 AS cohort_diag_intensity_95th_pct,
  cs.median_icu_los_days AS cohort_median_icu_los_days,
  ROUND(cs.hospital_mortality_rate * 100, 2) AS cohort_inhospital_mortality_pct,
  os.overall_icustay_count,
  os.overall_median_icu_los_days,
  ROUND(os.overall_hospital_mortality_rate * 100, 2) AS overall_inhospital_mortality_pct
FROM cohort_stats cs
CROSS JOIN overall_stats os;