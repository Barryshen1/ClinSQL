WITH
SurgicalHadms AS (
  -- Define surgical admissions by looking at the services provided
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.services`
  WHERE curr_service IN (
    'CSURG', -- Cardiac Surgery
    'NSURG', -- Neuro-surgery
    'ORTHO', -- Orthopedics
    'SURG',  -- General Surgery
    'TRAUM', -- Trauma
    'TSURG', -- Thoracic Surgery
    'VSURG', -- Vascular Surgery
    'GYN'    -- Gynecology
  )
),
Cohort AS (
  -- Select the cohort of female surgical patients aged 51-61
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.hadm_id IN (SELECT hadm_id FROM SurgicalHadms)
    AND p.gender = 'F'
    -- Calculate age at admission and filter
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 51 AND 61
),
Readmissions AS (
  -- Calculate LOS and 30-day readmission flag for the cohort
  WITH AllAdmissionsRanked AS (
    SELECT
      subject_id,
      admittime,
      dischtime,
      LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  )
  SELECT
    c.hadm_id,
    c.hospital_expire_flag,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(aar.next_admittime, c.dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS readmit_30_day_flag
  FROM Cohort AS c
  LEFT JOIN AllAdmissionsRanked AS aar
    ON c.subject_id = aar.subject_id AND c.admittime = aar.admittime
),
Medications AS (
  -- Find all medications administered in the first 24 hours of the stay
  SELECT
    c.hadm_id,
    LOWER(pr.drug) AS drug
  FROM Cohort AS c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON c.hadm_id = pr.hadm_id
  WHERE
    -- Prescription interval overlaps with first 24h of admission
    pr.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
    AND (pr.stoptime IS NULL OR pr.stoptime >= c.admittime)
),
MedComplexity AS (
  -- Calculate the medication complexity score for each admission
  SELECT
    hadm_id,
    -- Score = (unique drugs) + (sum of high-risk class indicators)
    COUNT(DISTINCT drug) + (
      -- Anticoagulants / Antiplatelets: +1 if any present
      MAX(CASE WHEN
        drug LIKE 'heparin%' OR drug LIKE 'warfarin%' OR drug LIKE 'enoxaparin%' OR
        drug LIKE 'argatroban%' OR drug LIKE 'bivalirudin%' OR drug LIKE 'fondaparinux%' OR
        drug LIKE 'aspirin%' OR drug LIKE 'clopidogrel%' OR drug LIKE 'ticagrelor%' OR
        drug LIKE 'prasugrel%' OR drug LIKE 'rivaroxaban%' OR drug LIKE 'apixaban%' OR
        drug LIKE 'dabigatran%'
      THEN 1 ELSE 0 END) +
      -- Insulins: +1 if any present
      MAX(CASE WHEN drug LIKE 'insulin%' THEN 1 ELSE 0 END) +
      -- Opioids: +1 if any present
      MAX(CASE WHEN
        drug LIKE 'morphine%' OR drug LIKE 'hydromorphone%' OR drug LIKE 'fentanyl%' OR
        drug LIKE 'oxycodone%' OR drug LIKE 'methadone%' OR drug LIKE 'remifentanil%' OR
        drug LIKE 'meperidine%' OR drug LIKE 'codeine%' OR drug LIKE 'tramadol%'
      THEN 1 ELSE 0 END) +
      -- Sedatives: +1 if any present
      MAX(CASE WHEN
        drug LIKE 'propofol%' OR drug LIKE 'dexmedetomidine%' OR drug LIKE 'midazolam%' OR
        drug LIKE 'lorazepam%' OR drug LIKE 'diazepam%' OR drug LIKE 'phenobarbital%' OR
        drug LIKE 'ketamine%'
      THEN 1 ELSE 0 END) +
      -- Vasopressors / Inotropes: +1 if any present
      MAX(CASE WHEN
        drug LIKE 'norepinephrine%' OR drug LIKE 'epinephrine%' OR drug LIKE 'vasopressin%' OR
        drug LIKE 'dopamine%' OR drug LIKE 'phenylephrine%' OR drug LIKE 'dobutamine%' OR
        drug LIKE 'milrinone%'
      THEN 1 ELSE 0 END)
    ) AS med_complexity_score
  FROM Medications
  GROUP BY hadm_id
),
Combined AS (
  -- Join outcomes with medication complexity scores
  SELECT
    r.hadm_id,
    r.los_days,
    r.hospital_expire_flag,
    r.readmit_30_day_flag,
    COALESCE(mc.med_complexity_score, 0) AS med_complexity_score
  FROM Readmissions AS r
  LEFT JOIN MedComplexity AS mc
    ON r.hadm_id = mc.hadm_id
),
Quartiles AS (
  -- Stratify admissions into quartiles based on complexity score
  SELECT
    hadm_id,
    los_days,
    hospital_expire_flag,
    readmit_30_day_flag,
    med_complexity_score,
    NTILE(4) OVER (ORDER BY med_complexity_score) AS complexity_quartile
  FROM Combined
)
-- Final report: aggregate metrics by complexity quartile
SELECT
  complexity_quartile,
  COUNT(hadm_id) AS number_of_admissions,
  MIN(med_complexity_score) AS min_complexity_score_in_quartile,
  MAX(med_complexity_score) AS max_complexity_score_in_quartile,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(readmit_30_day_flag) * 100, 2) AS readmission_30_day_pct
FROM Quartiles
GROUP BY complexity_quartile
ORDER BY complexity_quartile;