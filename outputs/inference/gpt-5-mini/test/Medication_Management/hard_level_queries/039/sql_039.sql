WITH cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    -- 30-day readmission flag: any subsequent admission for same subject within 30 days after discharge
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = a.subject_id
          AND a2.admittime > a.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0
    END AS readmit30_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- diagnose ICH by text matches in diagnosis descriptions
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code
        AND SAFE_CAST(di.icd_version AS STRING) = SAFE_CAST(d.icd_version AS STRING)
      WHERE di.hadm_id = a.hadm_id
        AND (
          LOWER(d.long_title) LIKE '%intracerebral%' OR
          LOWER(d.long_title) LIKE '%intracranial%' OR
          LOWER(d.long_title) LIKE '%subarachnoid%' OR
          LOWER(d.long_title) LIKE '%subdural%' OR
          LOWER(d.long_title) LIKE '%epidural%' OR
          LOWER(d.long_title) LIKE '%hemorrhag%'
        )
    )
),

-- Union medication events from hospital module (prescriptions, pharmacy, emar)
hosp_med_events AS (
  -- prescriptions
  SELECT
    subject_id,
    hadm_id,
    starttime AS event_time,
    TRIM(drug) AS drug,
    TRIM(route) AS route
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE starttime IS NOT NULL
    AND drug IS NOT NULL
    AND TRIM(drug) != ''

  UNION ALL

  -- pharmacy dispenses
  SELECT
    subject_id,
    hadm_id,
    starttime AS event_time,
    TRIM(medication) AS drug,
    TRIM(route) AS route
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE starttime IS NOT NULL
    AND medication IS NOT NULL
    AND TRIM(medication) != ''

  UNION ALL

  -- emar + emar_detail (med administration records with route in detail)
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime AS event_time,
    TRIM(e.medication) AS drug,
    TRIM(ed.route) AS route
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.subject_id = ed.subject_id
    AND e.emar_id = ed.emar_id
    AND e.emar_seq = ed.emar_seq
  WHERE e.charttime IS NOT NULL
    AND e.medication IS NOT NULL
    AND TRIM(e.medication) != ''
),

-- ICU medication-related events (map itemid to d_items.label when available)
icu_med_events AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.starttime AS event_time,
    TRIM(COALESCE(di.label, ie.ordercategoryname, ie.ordercomponenttypedescription)) AS drug,
    NULL AS route
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE ie.starttime IS NOT NULL
    AND COALESCE(di.label, ie.ordercategoryname, ie.ordercomponenttypedescription) IS NOT NULL
    AND TRIM(COALESCE(di.label, ie.ordercategoryname, ie.ordercomponenttypedescription)) != ''

  UNION ALL

  SELECT
    ing.subject_id,
    ing.hadm_id,
    ing.starttime AS event_time,
    TRIM(COALESCE(di.label, ing.statusdescription)) AS drug,
    NULL AS route
  FROM `physionet-data.mimiciv_3_1_icu.ingredientevents` ing
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ing.itemid = di.itemid
  WHERE ing.starttime IS NOT NULL
    AND COALESCE(di.label, ing.statusdescription) IS NOT NULL
    AND TRIM(COALESCE(di.label, ing.statusdescription)) != ''

  UNION ALL

  SELECT
    pe.subject_id,
    pe.hadm_id,
    pe.starttime AS event_time,
    TRIM(COALESCE(di.label, pe.ordercategoryname, pe.ordercomponenttypedescription)) AS drug,
    NULL AS route
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE pe.starttime IS NOT NULL
    AND COALESCE(di.label, pe.ordercategoryname, pe.ordercomponenttypedescription) IS NOT NULL
    AND TRIM(COALESCE(di.label, pe.ordercategoryname, pe.ordercomponenttypedescription)) != ''
),

-- All med events combined
med_events AS (
  SELECT * FROM hosp_med_events
  UNION ALL
  SELECT * FROM icu_med_events
),

-- Meds observed in the first 48 hours for cohort admissions
meds_in_48h AS (
  SELECT
    me.hadm_id,
    LOWER(TRIM(me.drug)) AS drug_l,
    LOWER(TRIM(COALESCE(me.route, 'UNK'))) AS route_l
  FROM med_events me
  JOIN cohort_admissions ca
    ON me.hadm_id = ca.hadm_id
  WHERE me.event_time BETWEEN ca.admittime AND TIMESTAMP_ADD(ca.admittime, INTERVAL 48 HOUR)
    AND me.drug IS NOT NULL
    AND TRIM(me.drug) != ''
),

-- Complexity score per admission = distinct (drug, route) count in first 48h
med_complexity AS (
  SELECT
    ca.hadm_id,
    COALESCE(cnt, 0) AS complexity_score
  FROM cohort_admissions ca
  LEFT JOIN (
    SELECT
      hadm_id,
      COUNT(DISTINCT CONCAT(drug_l, '||', route_l)) AS cnt
    FROM meds_in_48h
    GROUP BY hadm_id
  ) m
  USING (hadm_id)
),

-- Assign quartiles based on complexity score (NTILE) and bring along admission details
quartiled AS (
  SELECT
    mc.hadm_id,
    mc.complexity_score,
    ca.subject_id,
    ca.admittime,
    ca.dischtime,
    ca.hospital_expire_flag,
    ca.readmit30_flag,
    -- compute LOS in days as hours/24 (fractional)
    TIMESTAMP_DIFF(ca.dischtime, ca.admittime, HOUR) / 24.0 AS los_days,
    NTILE(4) OVER (ORDER BY mc.complexity_score) AS quartile
  FROM med_complexity mc
  JOIN cohort_admissions ca USING (hadm_id)
)

-- Final aggregation by quartile
SELECT
  quartile,
  COUNT(1) AS admissions_count,
  CONCAT(CAST(MIN(complexity_score) AS STRING), ' - ', CAST(MAX(complexity_score) AS STRING)) AS score_range,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(100.0 * SUM(IF(hospital_expire_flag=1,1,0)) / COUNT(1), 2) AS mortality_pct,
  ROUND(100.0 * SUM(IF(readmit30_flag=1,1,0)) / COUNT(1), 2) AS readmit30_pct
FROM quartiled
GROUP BY quartile
ORDER BY quartile;