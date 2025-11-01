WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hospital_los,
    a.hospital_expire_flag AS died_in_hosp
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND (
      (d.icd_version = 9 AND d.icd_code BETWEEN '53200' AND '53491')
      OR
      (d.icd_version = 10 AND d.icd_code IN ('K922', 'K250', 'K251', 'K252', 'K254', 'K256', 'K260', 'K261', 'K262', 'K264', 'K266', 'K270', 'K271', 'K272', 'K274', 'K276', 'K280', 'K281', 'K282', 'K284', 'K286'))
    )
    AND d.seq_num = 1
    AND i.intime = (
      SELECT MIN(intime)
      FROM physionet-data.mimiciv_3_1_icu.icustays i2
      WHERE i2.hadm_id = a.hadm_id
    )
),

procedures_first_72hr AS (
  SELECT
    c.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM
    cohort c
  JOIN
    physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON c.stay_id = pe.stay_id
  WHERE
    pe.starttime >= c.intime
    AND pe.starttime <= DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY
    c.stay_id
),

quartiles AS (
  SELECT
    c.*,
    COALESCE(p.procedure_count, 0) AS procedure_count,
    NTILE(4) OVER (ORDER BY COALESCE(p.procedure_count, 0)) AS quartile
  FROM
    cohort c
  LEFT JOIN
    procedures_first_72hr p
    ON c.stay_id = p.stay_id
)

SELECT
  quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(hospital_los) AS mean_hospital_los,
  AVG(died_in_hosp) AS in_hospital_mortality
FROM
  quartiles
GROUP BY
  quartile
ORDER BY
  quartile;