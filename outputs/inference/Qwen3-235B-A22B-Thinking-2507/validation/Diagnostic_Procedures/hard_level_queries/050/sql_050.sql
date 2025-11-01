WITH 
eligible_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 76 AND 86
),

ami_patients AS (
  SELECT 
    ep.*
  FROM eligible_patients ep
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = ep.hadm_id
      AND (
        (d.icd_version = 9 AND d.icd_code LIKE '410%')
        OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
      )
  )
),

first_icu AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
first_icu_stays AS (
  SELECT *
  FROM first_icu
  WHERE rn = 1
),

procedure_counts AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    COUNT(DISTINCT p.itemid) AS proc_count
  FROM first_icu_stays i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON i.stay_id = p.stay_id
    AND p.starttime >= i.intime
    AND p.starttime < DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY i.stay_id, i.hadm_id, i.intime, i.los
),

quartile_data AS (
  SELECT 
    pc.stay_id,
    pc.hadm_id,
    pc.proc_count,
    pc.los,
    ap.hospital_expire_flag,
    NTILE(4) OVER (ORDER BY pc.proc_count) AS quartile
  FROM procedure_counts pc
  INNER JOIN ami_patients ap
    ON pc.hadm_id = ap.hadm_id
)

SELECT 
  quartile,
  AVG(proc_count) AS mean_procedure_count,
  AVG(los) AS mean_icu_los,
  AVG(hospital_expire_flag) * 100 AS hospital_mortality_pct
FROM quartile_data
GROUP BY quartile
ORDER BY quartile;