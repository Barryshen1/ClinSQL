WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    a.hadm_id,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
  INNER JOIN (
    SELECT 
      subject_id, 
      stay_id,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS stay_order
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i_first 
    ON i.stay_id = i_first.stay_id AND i_first.stay_order = 1
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 88 AND 98
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE 
        di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code IN ('480', '481', '482', '483', '484', '485', '486', '487.0'))
          OR 
          (di.icd_version = 10 AND di.icd_code LIKE 'J1%')
        )
    )
),

all_events AS (
  SELECT 
    c.subject_id,
    c.stay_id,
    le.charttime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON c.subject_id = le.subject_id 
    AND le.charttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 72 HOUR)
  UNION ALL
  SELECT 
    c.subject_id,
    c.stay_id,
    m.charttime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` m 
    ON c.subject_id = m.subject_id 
    AND m.charttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 72 HOUR)
),

procedure_counts AS (
  SELECT 
    subject_id,
    stay_id,
    COUNT(*) AS procedure_count
  FROM all_events
  GROUP BY subject_id, stay_id
),

cohort_with_counts AS (
  SELECT 
    c.subject_id,
    c.stay_id,
    c.icu_los,
    c.hospital_expire_flag,
    COALESCE(pc.procedure_count, 0) AS procedure_count
  FROM cohort c
  LEFT JOIN procedure_counts pc 
    ON c.subject_id = pc.subject_id AND c.stay_id = pc.stay_id
),

quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM cohort_with_counts
)

SELECT 
  quintile,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(icu_los) AS avg_icu_los,
  100.0 * SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality_percent
FROM quintiles
GROUP BY quintile
ORDER BY quintile;