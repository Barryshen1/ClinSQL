WITH eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 78 AND 88
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code IN (
          '451.1', '451.11', '451.19', '451.9',  -- ICD-9
          'I82.2', 'I82.21', 'I82.29', 'I82.9'    -- ICD-10
        )
    )
),
admissions_with_los_icu AS (
  SELECT
    a.subject_id,  -- Qualified to resolve ambiguity
    a.hadm_id,     -- Qualified to resolve ambiguity
    a.admittime,
    a.dischtime,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE 'Other'
    END AS los_group,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_status
  FROM eligible_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8  -- Focus on LOS 1-8 days
),
noninvasive_events AS (
  -- Lab events (noninvasive categories)
  SELECT
    le.hadm_id,
    le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE
    li.category IN (
      'Urine', 'Stool', 'Sputum', 'Other Body Fluids', 'Cultures', 'Drug Screen',
      'Enzymes', 'Hormones', 'Lipids', 'Metabolic', 'Microbiology', 'Procedures',
      'Serology', 'Trace Elements', 'Urinalysis', 'Vitamins'
    )
    AND le.hadm_id IS NOT NULL
  UNION ALL
  -- Chart events (noninvasive categories) for ICU stays
  SELECT
    i.hadm_id,  -- Use i.hadm_id for consistency
    ce.charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON ce.stay_id = i.stay_id
  WHERE
    di.category IN (
      'Vitals', 'Cardiac', 'Glasgow Coma Scale', 'Intake and Output',
      'Respiratory', 'Temperature', 'Weights'
    )
    AND i.stay_id IS NOT NULL  -- Filter early for efficiency
),
noninvasive_counts AS (
  SELECT
    a.hadm_id,
    COUNT(ne.charttime) AS noninvasive_count
  FROM admissions_with_los_icu a
  LEFT JOIN noninvasive_events ne
    ON a.hadm_id = ne.hadm_id
    AND ne.charttime BETWEEN a.admittime AND a.dischtime
  GROUP BY a.hadm_id
)
SELECT
  aw.los_group,
  aw.icu_status,
  COUNT(aw.hadm_id) AS count_admissions,
  AVG(nc.noninvasive_count) AS mean_diagnostics_per_admission
FROM admissions_with_los_icu aw
LEFT JOIN noninvasive_counts nc
  ON aw.hadm_id = nc.hadm_id
WHERE
  aw.los_group IN ('1-4 days', '5-8 days')
GROUP BY aw.los_group, aw.icu_status
ORDER BY aw.los_group, aw.icu_status;