WITH age_filtered_acs AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    -- approximate age at admission: anchor_age + (year(admittime) - anchor_year)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 53 AND 63
    -- must have at least one ACS diagnosis in this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dcd
        ON di.icd_code = dcd.icd_code
       AND di.icd_version = dcd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          LOWER(dcd.long_title) LIKE '%acute myocardial infarction%'
          OR LOWER(dcd.long_title) LIKE '%unstable angina%'
          OR LOWER(dcd.long_title) LIKE '%acute coronary syndrome%'
        )
    )
),

-- Step 2: Compute per-admission 72h critical-lab score (ACS admissions)
-- Substep: per-admission score (count of distinct critical lab categories within 72h)
lab_crit_by_adm AS (
  SELECT
    af.subject_id,
    af.hadm_id,
    af.admittime,
    af.dischtime,
    af.hospital_expire_flag,
    COUNT(DISTINCT li.category) AS score
  FROM age_filtered_acs AS af
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = af.subject_id
   AND le.hadm_id = af.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON le.itemid = li.itemid
  WHERE le.charttime >= af.admittime
    AND le.charttime <= TIMESTAMP_ADD(af.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR
          (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
  GROUP BY af.subject_id, af.hadm_id, af.admittime, af.dischtime, af.hospital_expire_flag
),

-- Step 3: Attach score to ACS admissions (zero-fill if no critical labs for an admission)
acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    IFNULL(lc.score, 0) AS score
  FROM age_filtered_acs AS a
  LEFT JOIN lab_crit_by_adm AS lc
    ON a.subject_id = lc.subject_id
   AND a.hadm_id = lc.hadm_id
),

-- Step 4: Quartiles based on score
quartile_calc AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    score,
    NTILE(4) OVER (ORDER BY score) AS quartile
  FROM acs_admissions
),

-- Step 5: Summary per quartile (mortality and avg LOS)
quartile_summary AS (
  SELECT
    quartile,
    COUNT(*) AS n_patients,
    ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percent,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS avg_los_days
  FROM quartile_calc
  GROUP BY quartile
  ORDER BY quartile
),

-- Step 6: Age-matched female controls (53–63) without ACS in admission
controls_base AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.admittime,
    s.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM s.admittime) - p.anchor_year)) BETWEEN 53 AND 63
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dcd
        ON di.icd_code = dcd.icd_code
       AND di.icd_version = dcd.icd_version
      WHERE di.subject_id = s.subject_id
        AND di.hadm_id = s.hadm_id
        AND (
          LOWER(dcd.long_title) LIKE '%acute myocardial infarction%'
          OR LOWER(dcd.long_title) LIKE '%unstable angina%'
          OR LOWER(dcd.long_title) LIKE '%acute coronary syndrome%'
        )
    )
),

controls_lab_score AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    COUNT(DISTINCT li.category) AS score
  FROM controls_base AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = c.subject_id
   AND le.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON le.itemid = li.itemid
  WHERE le.charttime >= c.admittime
    AND le.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR
          (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime
),

controls_crit_rate AS (
  SELECT AVG(CASE WHEN sc.score > 0 THEN 1 ELSE 0 END) * 100 AS control_crit_rate
  FROM controls_lab_score sc
)

-- Step 7: Final results: ACS quartiles plus control rate
SELECT
  qc.quartile,
  qc.n_patients,
  qc.mortality_percent,
  qc.avg_los_days,
  cr.control_crit_rate
FROM quartile_summary AS qc
CROSS JOIN controls_crit_rate AS cr
ORDER BY qc.quartile;