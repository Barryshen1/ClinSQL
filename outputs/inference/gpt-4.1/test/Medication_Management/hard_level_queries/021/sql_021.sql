WITH cohort AS (
  -- Step 1: Get male inpatients aged 41-51
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
),

neutropenia_lab AS (
  -- Step 2a: Identify neutropenia by lab (ANC < 1.5 x10^9/L)
  SELECT
    l.subject_id,
    l.hadm_id,
    MIN(l.charttime) AS first_neutropenia_time
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%neutrophil%'
    AND l.valuenum IS NOT NULL
    AND l.valuenum < 1.5 -- x10^9/L
  GROUP BY l.subject_id, l.hadm_id
),

neutropenia_icd AS (
  -- Step 2b: Identify neutropenia by ICD code (D70*)
  SELECT
    di.subject_id,
    di.hadm_id,
    MIN(a.admittime) AS first_neutropenia_time
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON di.hadm_id = a.hadm_id
  WHERE
    (di.icd_version = 10 AND di.icd_code LIKE 'D70%')
    OR (di.icd_version = 9 AND di.icd_code LIKE '2880%')
  GROUP BY di.subject_id, di.hadm_id
),

fever AS (
  -- Step 3: Identify fever (temp >= 38°C) in first 48h
  SELECT
    ce.subject_id,
    ce.hadm_id,
    MIN(ce.charttime) AS first_fever_time
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%temperature%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum >= 38
  GROUP BY ce.subject_id, ce.hadm_id
),

qualifying_admissions AS (
  -- Step 4: Admissions with neutropenia (lab or ICD) AND fever in first 48h
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN neutropenia_lab nl
    ON c.subject_id = nl.subject_id AND c.hadm_id = nl.hadm_id
  LEFT JOIN neutropenia_icd ni
    ON c.subject_id = ni.subject_id AND c.hadm_id = ni.hadm_id
  LEFT JOIN fever f
    ON c.subject_id = f.subject_id AND c.hadm_id = f.hadm_id
  WHERE
    -- Neutropenia must occur in first 48h (lab or ICD)
    (
      (nl.first_neutropenia_time IS NOT NULL AND TIMESTAMP_DIFF(nl.first_neutropenia_time, c.admittime, HOUR) <= 48)
      OR
      (ni.first_neutropenia_time IS NOT NULL AND TIMESTAMP_DIFF(ni.first_neutropenia_time, c.admittime, HOUR) <= 48)
    )
    -- Fever must occur in first 48h
    AND f.first_fever_time IS NOT NULL
    AND TIMESTAMP_DIFF(f.first_fever_time, c.admittime, HOUR) <= 48
),

med_counts AS (
  -- Step 5: Count unique medications prescribed in first 48h
  SELECT
    qa.subject_id,
    qa.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count
  FROM qualifying_admissions qa
  JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON qa.subject_id = pr.subject_id AND qa.hadm_id = pr.hadm_id
    AND pr.starttime >= qa.admittime
    AND pr.starttime < TIMESTAMP_ADD(qa.admittime, INTERVAL 48 HOUR)
  GROUP BY qa.subject_id, qa.hadm_id
),

tertile_assign AS (
  -- Step 6: Assign tertiles by med_count
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.med_count,
    NTILE(3) OVER (ORDER BY mc.med_count) AS tertile
  FROM med_counts mc
),

final_cohort AS (
  -- Step 7: Merge outcomes
  SELECT
    ta.subject_id,
    ta.hadm_id,
    ta.med_count,
    ta.tertile,
    qa.admittime,
    qa.dischtime,
    qa.hospital_expire_flag,
    -- LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(qa.dischtime, qa.admittime, SECOND), 86400) AS los_days
  FROM tertile_assign ta
  JOIN qualifying_admissions qa
    ON ta.subject_id = qa.subject_id AND ta.hadm_id = qa.hadm_id
),

readmissions AS (
  -- Step 8: Find 30-day readmissions
  SELECT
    fc.subject_id,
    fc.hadm_id,
    MIN(a2.hadm_id) AS readmit_hadm_id
  FROM final_cohort fc
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a2
    ON fc.subject_id = a2.subject_id
    AND a2.admittime > fc.dischtime
    AND a2.admittime <= TIMESTAMP_ADD(fc.dischtime, INTERVAL 30 DAY)
  GROUP BY fc.subject_id, fc.hadm_id
),

summary AS (
  -- Step 9: Aggregate by tertile
  SELECT
    fc.tertile,
    COUNT(*) AS n_admissions,
    AVG(fc.los_days) AS avg_los_days,
    100.0 * SUM(CASE WHEN fc.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hosp_mortality_pct,
    100.0 * SUM(CASE WHEN r.readmit_hadm_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS readmit_30d_pct
  FROM final_cohort fc
  LEFT JOIN readmissions r
    ON fc.subject_id = r.subject_id AND fc.hadm_id = r.hadm_id
  GROUP BY fc.tertile
  ORDER BY fc.tertile
)

SELECT
  CASE summary.tertile
    WHEN 1 THEN 'Low'
    WHEN 2 THEN 'Mid'
    WHEN 3 THEN 'High'
    ELSE CAST(summary.tertile AS STRING)
  END AS medication_tertile,
  summary.n_admissions,
  ROUND(summary.avg_los_days, 2) AS avg_los_days,
  ROUND(summary.in_hosp_mortality_pct, 1) AS in_hosp_mortality_pct,
  ROUND(summary.readmit_30d_pct, 1) AS readmit_30d_pct
FROM summary;