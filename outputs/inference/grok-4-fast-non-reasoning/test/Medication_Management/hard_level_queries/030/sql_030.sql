WITH cohort AS (
  -- Base cohort: females 71-81 with primary acute pancreatitis
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND icd.icd_code LIKE 'K85.%'  -- Acute pancreatitis (ICD-10)
    AND d.seq_num = 1  -- Primary diagnosis
    AND (a.deathtime IS NULL OR DATETIME_DIFF(a.deathtime, a.admittime, HOUR) >= 72)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1  -- First matching admission per patient
),

readmissions AS (
  -- 30-day readmission flag
  SELECT 
    c.*,
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` r
        WHERE r.subject_id = c.subject_id
          AND r.hadm_id != c.hadm_id
          AND r.admittime > c.dischtime
          AND r.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS readmit_30d
  FROM 
    cohort c
),

med_orders AS (
  -- Medication orders from ICU inputevents (preferred)
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    COUNT(DISTINCT ie.orderid) AS med_count
  FROM 
    `physionet-data.mimiciv_3_1_icu.inputevents` ie
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  INNER JOIN 
    readmissions r
    ON ie.subject_id = r.subject_id AND ie.hadm_id = r.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ie.stay_id = icu.stay_id
  WHERE 
    di.category = 'Medications'  -- Medication administrations
    AND ie.starttime >= r.admittime
    AND ie.starttime <= DATETIME_ADD(r.admittime, INTERVAL 72 HOUR)
    AND ie.orderid IS NOT NULL
    AND (ie.statusdescription != 'Rewritten' OR ie.statusdescription IS NULL)  -- Active orders
  GROUP BY ie.subject_id, ie.hadm_id

  UNION ALL

  -- Fallback: hospital prescriptions if no ICU data
  SELECT 
    pr.subject_id,
    pr.hadm_id,
    COUNT(DISTINCT pr.poe_id) AS med_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN 
    readmissions r
    ON pr.subject_id = r.subject_id AND pr.hadm_id = r.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON pr.hadm_id = icu.hadm_id
  WHERE 
    icu.stay_id IS NULL  -- Only if no ICU stay
    AND pr.starttime >= r.admittime
    AND pr.starttime <= DATETIME_ADD(r.admittime, INTERVAL 72 HOUR)
    AND pr.poe_id IS NOT NULL
    AND pr.drug IS NOT NULL
  GROUP BY pr.subject_id, pr.hadm_id
),

med_summary AS (
  SELECT 
    r.*,
    COALESCE(m.med_count, 0) AS med_complexity_score
  FROM 
    readmissions r
  LEFT JOIN 
    med_orders m
    ON r.subject_id = m.subject_id AND r.hadm_id = m.hadm_id
),

tertiles AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY med_complexity_score) AS complexity_tertile  -- 1=low, 2=medium, 3=high
  FROM med_summary
)

-- Final aggregates per tertile
SELECT 
  complexity_tertile,
  COUNT(*) AS n_patients,
  AVG(los_days) AS avg_los_days,
  STDDEV(los_days) AS sd_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hosp_mortality_pct,
  AVG(readmit_30d) * 100 AS readmit_30d_pct,
  AVG(med_complexity_score) AS avg_med_score
FROM tertiles
GROUP BY complexity_tertile
ORDER BY complexity_tertile;