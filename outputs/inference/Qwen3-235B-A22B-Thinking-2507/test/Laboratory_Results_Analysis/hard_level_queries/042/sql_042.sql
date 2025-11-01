WITH patients_cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 73 AND 83
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code = '431')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I61%')
          OR LOWER(dd.long_title) LIKE '%intracerebral hemorrhage%'
        )
    )
),

instability_scores AS (
  SELECT 
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    COUNT(DISTINCT le.itemid) AS instability_score
  FROM patients_cohort pc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pc.subject_id = le.subject_id
    AND pc.hadm_id = le.hadm_id
    AND le.charttime >= pc.admittime
    AND le.charttime <= DATETIME_ADD(pc.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
    AND (
      (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
      OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
    )
  GROUP BY pc.subject_id, pc.hadm_id, pc.admittime
),

cohort_with_score AS (
  SELECT 
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    pc.dischtime,
    pc.hospital_expire_flag,
    COALESCE(iscore.instability_score, 0) AS instability_score
  FROM patients_cohort pc
  LEFT JOIN instability_scores iscore
    ON pc.subject_id = iscore.subject_id 
    AND pc.hadm_id = iscore.hadm_id
),

quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM cohort_with_score
),

critical_mortality AS (
  SELECT 
    AVG(hospital_expire_flag) AS critical_mortality_rate
  FROM quartiles
  WHERE quartile = 4
),

overall_mortality AS (
  SELECT 
    AVG(hospital_expire_flag) AS overall_mortality_rate
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
)

SELECT 
  q.quartile,
  COUNT(*) AS patient_count,
  AVG(TIMESTAMP_DIFF(q.dischtime, q.admittime, MICROSECOND) / (1000000 * 60 * 60 * 24)) AS mean_los_days,
  AVG(q.hospital_expire_flag) AS mortality_rate,
  cm.critical_mortality_rate,
  om.overall_mortality_rate
FROM quartiles q
CROSS JOIN critical_mortality cm
CROSS JOIN overall_mortality om
GROUP BY q.quartile, cm.critical_mortality_rate, om.overall_mortality_rate
ORDER BY q.quartile;