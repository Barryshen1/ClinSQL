WITH first_icustays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
  )
  WHERE rn = 1
),
sepsis_admissions AS (
  -- Admissions with any diagnosis whose description contains "sepsis" (ICD-9/10)
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
),
cohort AS (
  -- First ICU stays for female patients aged 66-76 (anchor_age)
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.outtime,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM first_icustays f
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON f.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
),
cohort_with_sepsis_flag AS (
  SELECT
    c.*,
    CASE WHEN s.hadm_id IS NOT NULL THEN TRUE ELSE FALSE END AS has_sepsis
  FROM cohort c
  LEFT JOIN sepsis_admissions s
    ON c.hadm_id = s.hadm_id
),
proc_counts AS (
  -- Count distinct ICD procedure codes during first 48 hours of ICU stay (chartdate is DATE)
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.anchor_age,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.has_sepsis,
    COALESCE(p_counts.proc_count, 0) AS proc_count
  FROM cohort_with_sepsis_flag c
  LEFT JOIN (
    SELECT
      hadm_id,
      COUNT(DISTINCT icd_code) AS proc_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    GROUP BY hadm_id
  ) p_counts
    ON p_counts.hadm_id = c.hadm_id
  -- Note: the above simple aggregation counts all procedures for the admission.
  -- To restrict to first 48 hours by chartdate, we re-calc below with a JOIN that uses the intime window:
),
proc_counts_48h AS (
  -- This CTE calculates procedure counts strictly within DATE(intime) .. DATE(intime + 48 hours)
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.anchor_age,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.has_sepsis,
    COALESCE(pc.proc_count_48h, 0) AS proc_count
  FROM cohort_with_sepsis_flag c
  LEFT JOIN (
    SELECT
      c2.hadm_id,
      COUNT(DISTINCT pr.icd_code) AS proc_count_48h
    FROM cohort_with_sepsis_flag c2
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      ON pr.hadm_id = c2.hadm_id
     AND pr.chartdate BETWEEN DATE(c2.intime)
                        AND DATE(TIMESTAMP_ADD(c2.intime, INTERVAL 48 HOUR))
    GROUP BY c2.hadm_id
  ) pc
    ON pc.hadm_id = c.hadm_id
),
final AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    anchor_age,
    admittime,
    dischtime,
    hospital_expire_flag,
    has_sepsis,
    proc_count,
    -- hospital LOS in days (fractional)
    SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, SECOND), 86400.0) AS los_days
  FROM proc_counts_48h
  WHERE admittime IS NOT NULL AND dischtime IS NOT NULL
),
sepsis_proc_90 AS (
  -- 90th percentile of procedure counts among sepsis cases
  SELECT
    (APPROX_QUANTILES(proc_count, 100))[OFFSET(90)] AS proc_90th
  FROM final
  WHERE has_sepsis = TRUE
),
group_summary AS (
  SELECT
    has_sepsis,
    COUNT(*) AS n_patients,
    AVG(los_days) AS mean_los_days,
    (APPROX_QUANTILES(los_days, 100))[OFFSET(50)] AS median_los_days,
    -- mortality rate: fraction with hospital_expire_flag = 1
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS mortality_rate,
    AVG(proc_count) AS mean_proc_count,
    (APPROX_QUANTILES(proc_count, 100))[OFFSET(50)] AS median_proc_count
  FROM final
  GROUP BY has_sepsis
)

SELECT
  gs.has_sepsis AS sepsis_flag,
  gs.n_patients,
  gs.mean_los_days,
  gs.median_los_days,
  gs.mortality_rate,
  gs.mean_proc_count,
  gs.median_proc_count,
  -- attach the 90th percentile only for the sepsis group (NULL for control row)
  CASE WHEN gs.has_sepsis THEN sp.proc_90th ELSE NULL END AS proc_count_90th_for_sepsis
FROM group_summary gs
LEFT JOIN sepsis_proc_90 sp
  ON TRUE
ORDER BY sepsis_flag DESC;