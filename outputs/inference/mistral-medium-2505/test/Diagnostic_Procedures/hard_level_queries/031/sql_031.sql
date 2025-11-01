WITH
-- Get male patients aged 66-76 with HHS-related diagnoses
hhs_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND d.icd_code IN ('K7682', 'K7460', 'K7469') -- HHS and related cirrhosis codes
    AND a.hospital_expire_flag IS NOT NULL
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) AS icu_los_hours
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    hhs_patients h ON s.subject_id = h.subject_id AND s.hadm_id = h.hadm_id
),

-- Count procedures within first 48 hours of ICU stay
procedure_counts AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM
    icu_stays i
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON i.subject_id = p.subject_id
    AND i.hadm_id = p.hadm_id
    AND i.stay_id = p.stay_id
    AND TIMESTAMP_DIFF(p.starttime, i.icu_intime, HOUR) <= 48
  GROUP BY
    i.stay_id, i.hadm_id
),

-- Calculate quintiles for procedure burden
quintiles AS (
  SELECT
    stay_id,
    hadm_id,
    procedure_count,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM
    procedure_counts
),

-- Calculate hospital LOS
hospital_los AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24 AS los_days
  FROM
    hhs_patients
),

-- Identify 30-day readmissions
readmissions AS (
  SELECT
    a1.subject_id,
    a1.hadm_id AS original_hadm_id,
    a2.hadm_id AS readmit_hadm_id,
    TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) AS days_to_readmit
  FROM
    hhs_patients a1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) <= 30
  WHERE
    a1.hadm_id != a2.hadm_id
),

-- Final aggregation by quintile
final_results AS (
  SELECT
    q.quintile,
    COUNT(DISTINCT q.stay_id) AS icu_stay_count,
    AVG(q.procedure_count) AS mean_procedures,
    MIN(q.procedure_count) AS min_procedures,
    MAX(q.procedure_count) AS max_procedures,
    AVG(CASE WHEN h.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS hospital_mortality_pct,
    AVG(l.los_days) AS mean_hospital_los_days,
    COUNT(DISTINCT CASE WHEN r.original_hadm_id = q.hadm_id THEN r.original_hadm_id END) /
      COUNT(DISTINCT q.hadm_id) * 100 AS readmission_30day_pct
  FROM
    quintiles q
  JOIN
    hhs_patients h ON q.hadm_id = h.hadm_id
  LEFT JOIN
    readmissions r ON q.hadm_id = r.original_hadm_id
  JOIN
    hospital_los l ON q.hadm_id = l.hadm_id
  GROUP BY
    q.quintile
)

SELECT * FROM final_results
ORDER BY quintile;