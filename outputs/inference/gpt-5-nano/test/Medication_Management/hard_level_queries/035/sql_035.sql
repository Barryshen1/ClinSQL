WITH base_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions AS a
  JOIN physionet-data.mimiciv_3_1_hosp.patients AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),
neutropenia_adm AS (
  SELECT DISTINCT bp.subject_id, bp.hadm_id
  FROM base_patients bp
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS di
    ON bp.subject_id = di.subject_id
   AND bp.hadm_id   = di.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%neutropenia%'
),
fever_adm AS (
  SELECT DISTINCT bp.subject_id, bp.hadm_id
  FROM base_patients bp
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS di
    ON bp.subject_id = di.subject_id
   AND bp.hadm_id = di.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%fever%'
),
cohort AS (
  SELECT bp.subject_id, bp.hadm_id, bp.admittime, bp.dischtime, bp.hospital_expire_flag
  FROM base_patients bp
  JOIN neutropenia_adm na
    ON bp.subject_id = na.subject_id
   AND bp.hadm_id = na.hadm_id
  JOIN fever_adm fa
    ON bp.subject_id = fa.subject_id
   AND bp.hadm_id = fa.hadm_id
),
mcs_cte AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS LOS,
    COUNT(DISTINCT pr.drug) AS mcs
  FROM cohort AS c
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.prescriptions AS pr
    ON pr.subject_id = c.subject_id
   AND pr.hadm_id   = c.hadm_id
   AND pr.starttime >= c.admittime
   AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 2 DAY)
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
mortality_cte AS (
  SELECT m.*,
         CASE WHEN m.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality
  FROM mcs_cte AS m
),
readmit_cte AS (
  SELECT mr.subject_id, mr.hadm_id, mr.admittime, mr.dischtime, mr.LOS, mr.mcs, mr.mortality
  FROM mortality_cte AS mr
),
final_with_readmit AS (
  SELECT
    r.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM physionet-data.mimiciv_3_1_hosp.admissions a2
        WHERE a2.subject_id = r.subject_id
          AND a2.admittime > r.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(r.dischtime, INTERVAL 30 DAY)
      ) THEN 1 ELSE 0
    END AS readmit30
  FROM readmit_cte AS r
)
SELECT
  quartile AS quartile,
  COUNT(*) AS patient_count,
  AVG(mcs) AS mean_mcs,
  MIN(mcs) AS min_mcs,
  MAX(mcs) AS max_mcs,
  AVG(LOS) AS mean_los,
  AVG(mortality) AS mortality_rate,
  AVG(readmit30) AS readmit_30_rate
FROM (
  SELECT
    f.*,
    NTILE(4) OVER (ORDER BY mcs) AS quartile
  FROM final_with_readmit AS f
) AS q
GROUP BY quartile
ORDER BY quartile;