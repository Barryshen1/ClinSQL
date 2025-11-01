WITH cohort AS (
  SELECT 
    i.stay_id,
    i.intime,
    i.outtime,
    p.subject_id,
    i.hadm_id,
    a.admittime,
    p.anchor_year,
    p.anchor_age,
    DATE_DIFF(
      CAST(a.admittime AS DATE), 
      DATE_SUB(
        DATE(CAST(p.anchor_year AS INT64), 1, 1), 
        INTERVAL p.anchor_age YEAR
      ), 
      YEAR
    ) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p 
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a 
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND DATE_DIFF(
      CAST(a.admittime AS DATE), 
      DATE_SUB(
        DATE(CAST(p.anchor_year AS INT64), 1, 1), 
        INTERVAL p.anchor_age YEAR
      ), 
      YEAR
    ) BETWEEN 59 AND 69
),
max_sbp AS (
  SELECT 
    co.stay_id,
    MAX(c.valuenum) AS max_systolic_bp
  FROM cohort co
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents c 
    ON co.stay_id = c.stay_id
  INNER JOIN (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu`.d_items 
    WHERE LOWER(label) LIKE '%systolic blood pressure%' 
       OR LOWER(label) LIKE '%sbp%'
  ) di ON c.itemid = di.itemid
  WHERE c.valuenum IS NOT NULL
    AND c.charttime >= co.intime
    AND c.charttime <= co.outtime
  GROUP BY co.stay_id
  HAVING max_systolic_bp IS NOT NULL
)
SELECT APPROX_QUANTILES(max_systolic_bp, 5)[OFFSET(3)] AS p75_max_sbp
FROM max_sbp;