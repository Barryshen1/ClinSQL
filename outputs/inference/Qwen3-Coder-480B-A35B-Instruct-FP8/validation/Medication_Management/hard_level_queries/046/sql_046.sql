WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.admission_type <> 'OUTPATIENT'
),

-- Identify multi-trauma admissions
multi_trauma AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT di.icd_code) AS trauma_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    (di.icd_version = 9 AND di.icd_code LIKE '80%')
    OR (di.icd_version = 10 AND di.icd_code LIKE 'S%')
  GROUP BY
    hadm_id
  HAVING
    COUNT(DISTINCT di.icd_code) >= 2
),

-- Medication complexity: distinct meds in first 7 days of ICU stay
med_complexity AS (
  SELECT
    e.hadm_id,
    e.subject_id,
    COUNT(DISTINCT e.medication) AS med_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN
    cohort c
  ON
    e.hadm_id = c.hadm_id
  WHERE
    e.charttime >= c.intime
    AND e.charttime <= DATETIME_ADD(c.intime, INTERVAL 7 DAY)
  GROUP BY
    e.hadm_id, e.subject_id
),

-- Combine cohort with multi-trauma and medication complexity
combined AS (
  SELECT
    c.*,
    COALESCE(m.med_count, 0) AS med_count
  FROM
    cohort c
  JOIN
    multi_trauma mt
  ON
    c.hadm_id = mt.hadm_id
  LEFT JOIN
    med_complexity m
  ON
    c.hadm_id = m.hadm_id
),

-- Tertiles of medication complexity
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY med_count) AS tertile
  FROM
    combined
),

-- 30-day readmission flag
readmissions AS (
  SELECT
    a1.subject_id,
    a1.hadm_id AS first_hadm_id,
    a2.hadm_id AS readmit_hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmit_30day
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a1
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
  ON
    a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND DATETIME_DIFF(a2.admittime, a1.dischtime, DAY) <= 30
  WHERE
    a1.hadm_id IN (SELECT hadm_id FROM combined)
)

-- Final aggregation by tertile
SELECT
  t.tertile,
  COUNT(DISTINCT t.hadm_id) AS admissions,
  AVG(t.med_count) AS mean_med_complexity,
  MIN(t.med_count) AS min_med_complexity,
  MAX(t.med_count) AS max_med_complexity,
  AVG(t.los) AS mean_los,
  AVG(t.hospital_expire_flag) AS mortality_rate,
  AVG(r.readmit_30day) AS readmit_30day_rate
FROM
  tertiles t
LEFT JOIN
  readmissions r
ON
  t.hadm_id = r.first_hadm_id
GROUP BY
  t.tertile
ORDER BY
  t.tertile;