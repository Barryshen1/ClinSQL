WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 37 AND 47
),

icu_stays_with_procedure AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.deathtime,
    pa.hospital_expire_flag,
    pa.age_at_admission,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON pa.hadm_id = icu.hadm_id
  WHERE icu.intime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
      WHERE pi.hadm_id = pa.hadm_id
        AND pi.chartdate <= DATE(icu.intime)  -- Compare dates only
    )
),

medication_complexity AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.subject_id,
    i.intime,
    i.outtime,
    i.dischtime,
    i.hospital_expire_flag,
    i.deathtime,
    i.admittime,
    COUNT(DISTINCT e.medication) AS unique_medications
  FROM icu_stays_with_procedure i
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.emar e
    ON i.hadm_id = e.hadm_id
    AND e.charttime >= i.intime
    AND e.charttime <= DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY i.stay_id, i.hadm_id, i.subject_id, i.intime, i.outtime, i.dischtime, i.hospital_expire_flag, i.deathtime, i.admittime
),

quintiles AS (
  SELECT
    *,
    NTILE(5) OVER (ORDER BY unique_medications) AS complexity_quintile
  FROM medication_complexity
),

readmissions AS (
  SELECT
    q.*,
    LEAD(q.admittime) OVER (PARTITION BY q.subject_id ORDER BY q.admittime) AS next_admittime
  FROM quintiles q
),

summary AS (
  SELECT
    complexity_quintile,
    AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24) AS avg_los_days,
    AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
    AVG(CASE 
          WHEN next_admittime IS NOT NULL 
           AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 
          THEN 1 ELSE 0 
        END) AS thirty_day_readmission_rate,
    COUNT(*) AS patient_count
  FROM readmissions
  GROUP BY complexity_quintile
  ORDER BY complexity_quintile
)

SELECT * FROM summary;