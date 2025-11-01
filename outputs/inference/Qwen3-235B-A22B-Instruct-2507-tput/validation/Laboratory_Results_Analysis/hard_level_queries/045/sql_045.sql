WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
),

asthma_exacerbation AS (
  SELECT DISTINCT pa.subject_id, pa.hadm_id, pa.admittime, pa.dischtime, pa.hospital_expire_flag, pa.deathtime
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%asthma exacerbation%'
     OR d.icd_code IN ('493.91', 'J45.901') -- Common codes for asthma exacerbation
),

lab_abnormalities_72h AS (
  SELECT
    ae.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM asthma_exacerbation ae
  JOIN `physionet-data.mimiciv_3_1_hosp`.labevents l
    ON ae.hadm_id = l.hadm_id
  WHERE l.charttime >= ae.admittime
    AND l.charttime <= ae.admittime + INTERVAL '72' HOUR
    AND (
      l.flag = 'abnormal'
      OR (l.valuenum IS NOT NULL AND l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
      OR (l.valuenum IS NOT NULL AND l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
    )
  GROUP BY ae.hadm_id
),

cohort_with_scores AS (
  SELECT
    ae.subject_id,
    ae.hadm_id,
    ae.admittime,
    ae.dischtime,
    ae.hospital_expire_flag,
    ae.deathtime,
    COALESCE(lab.critical_lab_count, 0) AS critical_lab_count
  FROM asthma_exacerbation ae
  LEFT JOIN lab_abnormalities_72h lab
    ON ae.hadm_id = lab.hadm_id
),

percentile_threshold AS (
  SELECT
    APPROX_QUANTILES(critical_lab_count, 100)[OFFSET(90)] AS p90_score
  FROM cohort_with_scores
),

cohort_with_group AS (
  SELECT
    cs.*,
    CASE
      WHEN cs.critical_lab_count >= pt.p90_score THEN 'Top Decile'
      ELSE 'Other'
    END AS risk_group
  FROM cohort_with_scores cs
  CROSS JOIN percentile_threshold pt
)

SELECT
  risk_group,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
  AVG(critical_lab_count) AS avg_critical_lab_events,
  COUNT(*) AS patient_count
FROM cohort_with_group
GROUP BY risk_group
ORDER BY risk_group DESC;