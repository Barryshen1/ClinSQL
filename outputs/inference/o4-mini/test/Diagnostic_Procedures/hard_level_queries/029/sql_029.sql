WITH
-- 1. Identify ICU stays for male patients age 68–78
icu_cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),

-- 2. Flag vasopressor exposure within 72 hours
vaso_exposed AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime
  FROM
    icu_cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
      ON c.subject_id = ie.subject_id
     AND c.hadm_id    = ie.hadm_id
     AND c.stay_id   = ie.stay_id
     AND ie.starttime BETWEEN c.intime
                         AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ie.itemid = di.itemid
  WHERE
    di.label IN ('Norepinephrine', 'Epinephrine', 'Vasopressin', 'Dopamine')
),

-- 3. Compute diagnostic load per stay (labs + imaging) within 72h
diag_counts AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    COUNT(DISTINCT l.labevent_id) AS lab_count,
    COUNT(DISTINCT STRUCT(h.chartdate, h.hcpcs_cd)) AS hcpcs_count,
    COUNT(DISTINCT l.labevent_id) + COUNT(DISTINCT STRUCT(h.chartdate, h.hcpcs_cd)) AS diag_count
  FROM
    vaso_exposed v
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON v.subject_id = l.subject_id
     AND v.hadm_id    = l.hadm_id
     AND l.charttime BETWEEN v.intime
                       AND TIMESTAMP_ADD(v.intime, INTERVAL 72 HOUR)
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
      ON v.subject_id = h.subject_id
     AND v.hadm_id    = h.hadm_id
     AND h.chartdate BETWEEN DATE(v.intime)
                       AND DATE(TIMESTAMP_ADD(v.intime, INTERVAL 72 HOUR))
  GROUP BY
    v.subject_id,
    v.hadm_id,
    v.stay_id
),

-- 4. Assign quartiles based on diag_count
quartiled AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    diag_count,
    NTILE(4) OVER (ORDER BY diag_count) AS diag_quartile
  FROM
    diag_counts
),

-- 5. Compute per‐admission outcomes
adm_outcomes AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.stay_id,
    q.diag_quartile,
    q.diag_count,
    COALESCE(proc.proc_count, 0) AS proc_count,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los,
    a.hospital_expire_flag AS mortality,
    CASE WHEN next_adm.next_hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmit_30d
  FROM
    quartiled q
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON q.hadm_id = a.hadm_id
    LEFT JOIN (
      SELECT
        hadm_id,
        COUNT(*) AS proc_count
      FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd`
      GROUP BY hadm_id
    ) proc
      ON q.hadm_id = proc.hadm_id
    LEFT JOIN (
      -- find next admission within 30 days
      SELECT
        a1.subject_id,
        a1.hadm_id,
        MIN(a2.hadm_id) AS next_hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a1
        JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
          ON a1.subject_id = a2.subject_id
         AND a2.admittime > a1.dischtime
         AND a2.admittime <= TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
      GROUP BY
        a1.subject_id,
        a1.hadm_id
    ) next_adm
      ON q.subject_id = next_adm.subject_id
     AND q.hadm_id    = next_adm.hadm_id
)

-- 6. Final aggregation by quartile
SELECT
  diag_quartile,
  ROUND(AVG(proc_count), 2)    AS avg_proc_count,
  ROUND(AVG(hosp_los),   2)    AS avg_hospital_los_days,
  ROUND(AVG(mortality),  3)    AS in_hospital_mortality_rate,
  ROUND(AVG(readmit_30d),3)    AS readmission_30d_rate
FROM
  adm_outcomes
GROUP BY
  diag_quartile
ORDER BY
  diag_quartile;