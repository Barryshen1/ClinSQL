WITH sepsis_hadm AS (
  -- admissions that have any diagnosis whose long_title mentions "sepsis"
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
),
icu_base AS (
  -- ICU stays for male patients age 90-100 with admissions info
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    USING (subject_id, hadm_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
sepsis_icustays AS (
  -- restrict to admissions with sepsis
  SELECT b.*
  FROM icu_base b
  WHERE b.hadm_id IN (SELECT hadm_id FROM sepsis_hadm)
),
total_group_icustays AS (
  -- total ICU stays for male patients age 90-100 (for comparison)
  SELECT * FROM icu_base
),
diag_counts AS (
  -- compute diagnostic counts within first 24 hours per sepsis icu stay
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.los,
    s.hospital_expire_flag,
    -- lab events (hospital labevents)
    (
      SELECT COUNT(1)
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
      WHERE le.hadm_id = s.hadm_id
        AND TIMESTAMP(COALESCE(le.charttime, le.storetime)) >= TIMESTAMP(s.intime)
        AND TIMESTAMP(COALESCE(le.charttime, le.storetime)) < TIMESTAMP_ADD(TIMESTAMP(s.intime), INTERVAL 24 HOUR)
    ) AS lab_count,
    -- microbiology events (hospital microbiologyevents)
    (
      SELECT COUNT(1)
      FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` me
      WHERE me.hadm_id = s.hadm_id
        AND TIMESTAMP(me.charttime) >= TIMESTAMP(s.intime)
        AND TIMESTAMP(me.charttime) < TIMESTAMP_ADD(TIMESTAMP(s.intime), INTERVAL 24 HOUR)
    ) AS micro_count,
    -- procedure events from ICU (often includes imaging/procedures)
    (
      SELECT COUNT(1)
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.hadm_id = s.hadm_id
        AND TIMESTAMP(pe.starttime) >= TIMESTAMP(s.intime)
        AND TIMESTAMP(pe.starttime) < TIMESTAMP_ADD(TIMESTAMP(s.intime), INTERVAL 24 HOUR)
    ) AS proc_count,
    -- hcpcsevents (chartdate is DATE; cast to TIMESTAMP at midnight)
    (
      SELECT COUNT(1)
      FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
      WHERE hc.hadm_id = s.hadm_id
        AND TIMESTAMP(hc.chartdate) >= TIMESTAMP(s.intime)
        AND TIMESTAMP(hc.chartdate) < TIMESTAMP_ADD(TIMESTAMP(s.intime), INTERVAL 24 HOUR)
    ) AS hcpcs_count
  FROM sepsis_icustays s
),
diag_per_stay AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    los,
    hospital_expire_flag,
    lab_count + micro_count + proc_count + hcpcs_count AS diag_count
  FROM diag_counts
)

-- final summary metrics
SELECT
  COUNT(*) AS n_sepsis_icustays,
  (SELECT COUNT(*) FROM total_group_icustays) AS n_total_icustays_male_90_100,
  ROUND(100.0 * COUNT(*) / NULLIF((SELECT COUNT(*) FROM total_group_icustays), 0), 2) AS pct_of_group_sepsis,
  -- SD of diagnostic utilization (population SD)
  ROUND(STDDEV_POP(diag_count), 3) AS sd_diag_first_24h,
  -- approximate percentiles
  (SELECT APPROX_QUANTILES(diag_count, 100)[OFFSET(75)] FROM diag_per_stay) AS p75_diag_first_24h,
  (SELECT APPROX_QUANTILES(diag_count, 100)[OFFSET(95)] FROM diag_per_stay) AS p95_diag_first_24h,
  -- in-hospital mortality % (based on admissions.hospital_expire_flag)
  ROUND(100.0 * AVG(CAST(hospital_expire_flag AS FLOAT64)), 2) AS in_hospital_mortality_pct,
  -- average ICU length of stay (days)
  ROUND(AVG(los), 3) AS avg_icu_los_days
FROM diag_per_stay;