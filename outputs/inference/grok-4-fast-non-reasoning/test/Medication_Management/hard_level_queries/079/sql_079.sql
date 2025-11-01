WITH cohort AS (
  -- Base cohort: males 89-99 with hemorrhagic stroke (primary diagnosis)
  SELECT 
    p.subject_id,
    a.hadm_id,
    TIMESTAMP(a.admittime) AS admittime,
    TIMESTAMP(a.dischtime) AS dischtime,
    a.hospital_expire_flag,
    a.los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 89 AND 99
    AND a.admission_type != 'OBSERVATION'  -- Exclude observation stays
    AND icd.icd_version = '10'
    AND (icd.icd_code LIKE 'I60%' OR icd.icd_code LIKE 'I61%')
    AND d.seq_num = 1  -- Primary diagnosis
    AND a.los > 0  -- Exclude LOS=0
),

med_complexity AS (
  -- Calculate unique drugs in first 7 days per admission
  SELECT 
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT pres.drug) AS med_complexity
  FROM 
    cohort c
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON c.subject_id = pres.subject_id 
    AND c.hadm_id = pres.hadm_id
    AND pres.drug IS NOT NULL 
    AND pres.drug != ''
    AND TIMESTAMP(pres.starttime) >= c.admittime
    AND TIMESTAMP(pres.starttime) < TIMESTAMP_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY 
    c.subject_id, c.hadm_id
),

readmissions AS (
  -- Flag 30-day readmission for each admission
  SELECT 
    *,
    CASE 
      WHEN next_admittime <= TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY) 
           AND next_admittime > dischtime 
      THEN 1 
      ELSE 0 
    END AS readmit_30d_flag
  FROM (
    SELECT 
      c.subject_id,
      c.hadm_id,
      c.admittime,
      c.dischtime,
      c.hospital_expire_flag,
      c.los,
      m.med_complexity,
      LEAD(TIMESTAMP(c.admittime)) OVER (PARTITION BY c.subject_id ORDER BY c.admittime) AS next_admittime
    FROM 
      cohort c
    LEFT JOIN 
      med_complexity m
      ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
  ) 
),

quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY med_complexity ASC) AS quintile
  FROM 
    readmissions
)

-- Final aggregates by quintile
SELECT 
  quintile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los), 2) AS avg_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS inpatient_mortality_pct,
  ROUND(AVG(readmit_30d_flag) * 100, 2) AS readmission_30d_pct
FROM 
  quintiles
GROUP BY 
  quintile
ORDER BY 
  quintile;