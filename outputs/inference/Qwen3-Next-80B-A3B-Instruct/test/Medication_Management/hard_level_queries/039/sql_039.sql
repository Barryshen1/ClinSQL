WITH ich_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND (
      LOWER(dicd.long_title) LIKE '%intracranial hemorrhage%'
      OR LOWER(dicd.long_title) LIKE '%subarachnoid%'
      OR LOWER(dicd.long_title) LIKE '%intracerebral%'
      OR LOWER(dicd.long_title) LIKE '%intracranial bleed%'
      OR LOWER(dicd.long_title) LIKE '%cerebral hemorrhage%'
      OR LOWER(dicd.long_title) LIKE '%hemorrhage, intracranial%'
      OR d.icd_code IN ('430', '431', '432', 'I60', 'I61', 'I62')
    )
),

first_icu_stay AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN ich_patients ip ON i.subject_id = ip.subject_id AND i.hadm_id = ip.hadm_id
),

filtered_icu_stays AS (
  SELECT *
  FROM first_icu_stay
  WHERE rn = 1
),

medication_complexity AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    COUNT(DISTINCT CONCAT(di.label, '|', COALESCE(ie.ordercategorydescription, 'Unknown'))) AS drug_route_count
  FROM filtered_icu_stays f
  LEFT JOIN physionet-data.mimiciv_3_1_icu.inputevents ie
    ON f.stay_id = ie.stay_id
    AND ie.starttime >= f.intime
    AND ie.starttime <= DATETIME_ADD(f.intime, INTERVAL 48 HOUR)
  LEFT JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ie.itemid = di.itemid
    AND di.linksto = 'inputevents'
  GROUP BY f.subject_id, f.hadm_id
),

quartiles AS (
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.drug_route_count,
    NTILE(4) OVER (ORDER BY mc.drug_route_count) AS quartile
  FROM medication_complexity mc
),

readmissions AS (
  SELECT
    a1.subject_id,
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM ich_patients a1
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.admissions a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= DATETIME_ADD(a1.dischtime, INTERVAL 30 DAY)
)

SELECT
  q.quartile,
  COUNT(q.subject_id) AS admissions,
  MIN(q.drug_route_count) AS min_complexity_score,
  MAX(q.drug_route_count) AS max_complexity_score,
  AVG(f.los) AS avg_los,
  AVG(CAST(i.hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent,
  AVG(CAST(r.readmitted_30d AS FLOAT64)) * 100 AS readmission_30d_percent
FROM quartiles q
JOIN filtered_icu_stays f ON q.subject_id = f.subject_id AND q.hadm_id = f.hadm_id
JOIN ich_patients i ON q.subject_id = i.subject_id AND q.hadm_id = i.hadm_id
LEFT JOIN readmissions r ON q.subject_id = r.subject_id AND q.hadm_id = r.hadm_id
GROUP BY q.quartile
ORDER BY q.quartile;