WITH pe_admissions AS (
  -- Step 1: Identify women aged 64–74 with PE
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
    AND (
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I26'))
      OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^4151'))
    )
),

med_complexity AS (
  -- Step 2: Count distinct meds in first 24h for each admission
  SELECT
    pe.subject_id,
    pe.hadm_id,
    pe.admittime,
    pe.dischtime,
    pe.hospital_expire_flag,
    pe.anchor_age,
    IFNULL(COUNT(DISTINCT pr.drug), 0) AS med_complexity
  FROM pe_admissions pe
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON pe.hadm_id = pr.hadm_id
    AND pr.starttime >= pe.admittime
    AND pr.starttime < DATETIME_ADD(pe.admittime, INTERVAL 24 HOUR)
  GROUP BY pe.subject_id, pe.hadm_id, pe.admittime, pe.dischtime, pe.hospital_expire_flag, pe.anchor_age
),

tertile_assign AS (
  -- Step 3: Assign tertiles based on med complexity
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    anchor_age,
    med_complexity,
    NTILE(3) OVER (ORDER BY med_complexity) AS tertile
  FROM med_complexity
),

readmissions AS (
  -- Step 4: Find 30-day readmissions for each admission
  SELECT
    curr.hadm_id,
    CASE WHEN MIN(next.admittime) IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM tertile_assign curr
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.admissions next
    ON curr.subject_id = next.subject_id
    AND next.admittime > curr.dischtime
    AND next.admittime <= DATETIME_ADD(curr.dischtime, INTERVAL 30 DAY)
  GROUP BY curr.hadm_id
),

final AS (
  -- Step 5: Combine all info
  SELECT
    CAST(t.tertile AS INT64) AS tertile,
    t.hadm_id,
    t.med_complexity,
    DATETIME_DIFF(t.dischtime, t.admittime, DAY) AS los,
    t.hospital_expire_flag,
    r.readmitted_30d
  FROM tertile_assign t
  LEFT JOIN readmissions r
    ON t.hadm_id = r.hadm_id
)

-- Step 6: Aggregate by tertile
SELECT
  tertile,
  COUNT(*) AS admissions,
  MIN(med_complexity) AS med_score_min,
  MAX(med_complexity) AS med_score_max,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS mortality_percent,
  ROUND(100 * SUM(readmitted_30d) / COUNT(*), 1) AS readmission_30d_percent
FROM final
GROUP BY tertile
ORDER BY tertile;