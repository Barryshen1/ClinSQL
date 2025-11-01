WITH cohort AS (
  -- Step 1: Identify male patients aged 68–78 with ICU stays
  SELECT DISTINCT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    DATETIME_ADD(i.intime, INTERVAL 72 HOUR) AS intime_72,
    i.outtime,
    a.dischtime,
    a.admittime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),

vaso AS (
  -- Step 2: Identify ICU stays with vasopressor use within 72 hours
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.intime_72
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.inputevents` iv
    ON c.stay_id = iv.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON iv.itemid = d.itemid
  WHERE
    d.category = 'VASOPRESSORS'
    AND iv.starttime BETWEEN c.intime AND c.intime_72
),

diagnostic_load AS (
  -- Step 3: Count labs and imaging procedures within 72 hours
  SELECT
    v.stay_id,
    COUNT(DISTINCT l.labevent_id) AS lab_count,
    COUNT(DISTINCT pr.seq_num) AS imaging_count
  FROM
    vaso v
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON v.hadm_id = l.hadm_id
    AND l.charttime BETWEEN v.intime AND v.intime_72
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON v.hadm_id = pr.hadm_id
    AND pr.chartdate BETWEEN DATE(v.intime) AND DATE(v.intime_72)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
    AND (
      UPPER(dpr.long_title) LIKE '%CT%'
      OR UPPER(dpr.long_title) LIKE '%MRI%'
      OR UPPER(dpr.long_title) LIKE '%XRAY%'
      OR UPPER(dpr.long_title) LIKE '%ULTRASOUND%'
    )
  GROUP BY
    v.stay_id
),

quartiles AS (
  -- Step 4: Stratify into quartiles by diagnostic load
  SELECT
    dl.stay_id,
    NTILE(4) OVER (ORDER BY (dl.lab_count + dl.imaging_count)) AS diagnostic_quartile
  FROM
    diagnostic_load dl
),

procedure_counts AS (
  -- Step 5: Count procedures per stay
  SELECT
    pr.hadm_id,
    COUNT(*) AS procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  GROUP BY
    pr.hadm_id
),

readmissions AS (
  -- Step 6: Identify 30-day readmissions
  SELECT
    a1.subject_id,
    a1.hadm_id AS first_hadm,
    a2.hadm_id AS readmit_hadm
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND DATETIME_DIFF(a2.admittime, a1.dischtime, DAY) <= 30
)

-- Final aggregation
SELECT
  q.diagnostic_quartile,
  AVG(pc.procedure_count) AS avg_procedure_count,
  AVG(DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS avg_hospital_los_days,
  AVG(a.hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(CASE WHEN r.readmit_hadm IS NOT NULL THEN 1 ELSE 0 END) AS readmission_30day_rate
FROM
  quartiles q
JOIN
  cohort c
  ON q.stay_id = c.stay_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON c.hadm_id = a.hadm_id
LEFT JOIN
  procedure_counts pc
  ON a.hadm_id = pc.hadm_id
LEFT JOIN
  readmissions r
  ON a.hadm_id = r.first_hadm
GROUP BY
  q.diagnostic_quartile
ORDER BY
  q.diagnostic_quartile;