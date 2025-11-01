WITH pneumonia_patients AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.subject_id = p.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(d.long_title) LIKE '%pneumonia%'
    )
),
first_24h_meds AS (
  SELECT 
    pp.subject_id,
    pp.hadm_id,
    COUNT(DISTINCT rx.drug) AS med_count,
    MAX(
      CASE WHEN LOWER(rx.drug) LIKE '%fluoxetine%' OR
                LOWER(rx.drug) LIKE '%sertraline%' OR
                LOWER(rx.drug) LIKE '%paroxetine%' OR
                LOWER(rx.drug) LIKE '%citalopram%' OR
                LOWER(rx.drug) LIKE '%escitalopram%' OR
                LOWER(rx.drug) LIKE '%fluvoxamine%' OR
                LOWER(rx.drug) LIKE '%venlafaxine%' OR
                LOWER(rx.drug) LIKE '%duloxetine%' OR
                LOWER(rx.drug) LIKE '%desvenlafaxine%' OR
                LOWER(rx.drug) LIKE '%amitriptyline%' OR
                LOWER(rx.drug) LIKE '%nortriptyline%' OR
                LOWER(rx.drug) LIKE '%imipramine%' OR
                LOWER(rx.drug) LIKE '%desipramine%' OR
                LOWER(rx.drug) LIKE '%clomipramine%' OR
                LOWER(rx.drug) LIKE '%phenelzine%' OR
                LOWER(rx.drug) LIKE '%tranylcypromine%' OR
                LOWER(rx.drug) LIKE '%isocarboxazid%' OR
                LOWER(rx.drug) LIKE '%selegiline%' OR
                LOWER(rx.drug) LIKE '%trazodone%' OR
                LOWER(rx.drug) LIKE '%nefazodone%' OR
                LOWER(rx.drug) LIKE '%vilazodone%' OR
                LOWER(rx.drug) LIKE '%vortioxetine%' OR
                LOWER(rx.drug) LIKE '%tramadol%' OR
                LOWER(rx.drug) LIKE '%meperidine%' OR
                LOWER(rx.drug) LIKE '%dextromethorphan%' OR
                LOWER(rx.drug) LIKE '%linezolid%' OR
                LOWER(rx.drug) LIKE '%sumatriptan%' OR
                LOWER(rx.drug) LIKE '%rizatriptan%' OR
                LOWER(rx.drug) LIKE '%almotriptan%' OR
                LOWER(rx.drug) LIKE '%naratriptan%' OR
                LOWER(rx.drug) LIKE '%frovatriptan%' OR
                LOWER(rx.drug) LIKE '%eletriptan%' OR
                LOWER(rx.drug) LIKE '%zolmitriptan%' 
           THEN 1 ELSE 0 END
    ) AS serotonergic_risk_flag
  FROM pneumonia_patients pp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON pp.subject_id = rx.subject_id
    AND pp.hadm_id = rx.hadm_id
  WHERE rx.starttime BETWEEN pp.admittime AND DATETIME_ADD(pp.admittime, INTERVAL 24 HOUR)
  GROUP BY pp.subject_id, pp.hadm_id
),
icu_stay_flag AS (
  SELECT 
    pp.subject_id,
    pp.hadm_id,
    CASE WHEN COUNT(i.stay_id) > 0 THEN 1 ELSE 0 END AS icu_patient_flag
  FROM pneumonia_patients pp
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON pp.subject_id = i.subject_id
    AND pp.hadm_id = i.hadm_id
  GROUP BY pp.subject_id, pp.hadm_id
),
final_cohort AS (
  SELECT 
    pp.*,
    COALESCE(fm.med_count, 0) AS med_count,
    COALESCE(fm.serotonergic_risk_flag, 0) AS serotonergic_risk_flag,
    icu.icu_patient_flag
  FROM pneumonia_patients pp
  LEFT JOIN first_24h_meds fm
    ON pp.subject_id = fm.subject_id AND pp.hadm_id = fm.hadm_id
  LEFT JOIN icu_stay_flag icu
    ON pp.subject_id = icu.subject_id AND pp.hadm_id = icu.hadm_id
  WHERE fm.med_count IS NOT NULL  -- Ensure only patients with meds in first 24h
),
med_complexity_stats AS (
  SELECT 
    'med_complexity' AS part,
    CAST(NULL AS STRING) AS group_name,
    'mean' AS metric,
    AVG(med_count) AS value
  FROM final_cohort
  UNION ALL
  SELECT 
    'med_complexity',
    CAST(NULL AS STRING),
    'p25',
    APPROX_QUANTILES(med_count, 4)[OFFSET(1)]
  FROM final_cohort
  UNION ALL
  SELECT 
    'med_complexity',
    CAST(NULL AS STRING),
    'p50',
    APPROX_QUANTILES(med_count, 4)[OFFSET(2)]
  FROM final_cohort
  UNION ALL
  SELECT 
    'med_complexity',
    CAST(NULL AS STRING),
    'p75',
    APPROX_QUANTILES(med_count, 4)[OFFSET(3)]
  FROM final_cohort
),
group_comparison AS (
  -- Serotonergic risk group
  SELECT 
    'group_comparison' AS part,
    'serotonergic_risk' AS group_name,
    'avg_los' AS metric,
    AVG(los_hospital) AS value
  FROM final_cohort
  WHERE serotonergic_risk_flag = 1
  UNION ALL
  SELECT 
    'group_comparison',
    'serotonergic_risk',
    'mortality_rate',
    AVG(hospital_expire_flag) AS value
  FROM final_cohort
  WHERE serotonergic_risk_flag = 1
  UNION ALL
  -- ICU group
  SELECT 
    'group_comparison',
    'icu_patient',
    'avg_los',
    AVG(los_hospital) AS value
  FROM final_cohort
  WHERE icu_patient_flag = 1
  UNION ALL
  SELECT 
    'group_comparison',
    'icu_patient',
    'mortality_rate',
    AVG(hospital_expire_flag) AS value
  FROM final_cohort
  WHERE icu_patient_flag = 1
),
top_quartile_los AS (
  WITH los_quartiles AS (
    SELECT APPROX_QUANTILES(los_hospital, 4) AS q_arr
    FROM final_cohort
  ),
  p75_value AS (
    SELECT q_arr[OFFSET(3)] AS p75_los
    FROM los_quartiles
  ),
  top_quartile_patients AS (
    SELECT hospital_expire_flag
    FROM final_cohort, p75_value
    WHERE los_hospital >= p75_los
  )
  SELECT 
    'top_quartile' AS part,
    CAST(NULL AS STRING) AS group_name,
    'p75_los' AS metric,
    (SELECT p75_los FROM p75_value) AS value
  FROM p75_value
  UNION ALL
  SELECT 
    'top_quartile',
    CAST(NULL AS STRING),
    'mortality_in_top_quartile',
    AVG(hospital_expire_flag) AS value
  FROM top_quartile_patients
)
SELECT part, group_name, metric, value
FROM med_complexity_stats
UNION ALL
SELECT part, group_name, metric, value
FROM group_comparison
UNION ALL
SELECT part, group_name, metric, value
FROM top_quartile_los;