WITH base_for_readmission AS (
  SELECT 
    subject_id, 
    hadm_id, 
    admittime, 
    dischtime, 
    hospital_expire_flag,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    a.hospital_expire_flag,
    a.next_admittime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN base_for_readmission a 
    ON p.subject_id = a.subject_id
  WHERE 
    a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.services` 
      WHERE 
        curr_service LIKE '%SURG%' OR 
        prev_service LIKE '%SURG%'
    )
    AND p.gender = 'F'
),
cohort_age_filtered AS (
  SELECT 
    *,
    CASE 
      WHEN next_admittime <= DATETIME_ADD(dischtime, INTERVAL 30 DAY) THEN 1
      ELSE 0 
    END AS readmission_30d
  FROM cohort
  WHERE age_admit BETWEEN 51 AND 61
),
meds_complexity AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT e.medication) AS distinct_drugs,
    COUNT(DISTINCT 
      CASE
        WHEN LOWER(e.medication) LIKE '%warfarin%' OR LOWER(e.medication) LIKE '%heparin%' 
             OR LOWER(e.medication) LIKE '%enoxaparin%' OR LOWER(e.medication) LIKE '%dalteparin%' THEN 'Anticoagulant'
        WHEN LOWER(e.medication) LIKE '%morphine%' OR LOWER(e.medication) LIKE '%fentanyl%' 
             OR LOWER(e.medication) LIKE '%oxycodone%' OR LOWER(e.medication) LIKE '%hydromorphone%' THEN 'Opioid'
        WHEN LOWER(e.medication) LIKE '%insulin%' THEN 'Insulin'
        WHEN LOWER(e.medication) LIKE '%vancomycin%' OR LOWER(e.medication) LIKE '%meropenem%' 
             OR LOWER(e.medication) LIKE '%piperacillin%' OR LOWER(e.medication) LIKE '%tazobactam%' THEN 'Antibiotic'
        ELSE NULL
      END
    ) AS distinct_risk_classes
  FROM cohort_age_filtered c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
    AND e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.hadm_id
),
cohort_with_complexity AS (
  SELECT 
    c.*,
    COALESCE(m.distinct_drugs, 0) + COALESCE(m.distinct_risk_classes, 0) AS complexity_index,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM cohort_age_filtered c
  LEFT JOIN meds_complexity m 
    ON c.hadm_id = m.hadm_id
),
cohort_quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY complexity_index) AS complexity_quartile
  FROM cohort_with_complexity
)
SELECT 
  complexity_quartile,
  COUNT(*) AS num_admissions,
  ROUND(AVG(los_days), 2) AS avg_los,
  ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_percent,
  ROUND(100 * AVG(readmission_30d), 2) AS readmission_30d_percent
FROM cohort_quartiles
GROUP BY complexity_quartile
ORDER BY complexity_quartile;