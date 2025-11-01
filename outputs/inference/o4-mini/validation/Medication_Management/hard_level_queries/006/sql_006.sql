WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.anchor_age,
    icu.intime,
    icu.outtime,
    icu.los,
    a.hospital_expire_flag,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admission_type = 'POSTOPERATIVE'
    -- only the first ICU stay per admission
    AND icu.intime = (
      SELECT MIN(intime)
      FROM `physionet-data.mimiciv_3_1_icu.icustays` ic2
      WHERE ic2.subject_id = icu.subject_id
        AND ic2.hadm_id    = icu.hadm_id
    )
),
med_items AS (
  SELECT subject_id, hadm_id, stay_id, itemid, starttime
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  UNION ALL
  SELECT subject_id, hadm_id, stay_id, itemid, starttime
  FROM `physionet-data.mimiciv_3_1_icu.ingredientevents`
),
meds AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(DISTINCT m.itemid) AS med_count
  FROM
    cohort c
    LEFT JOIN med_items m
      ON m.subject_id = c.subject_id
     AND m.hadm_id    = c.hadm_id
     AND m.stay_id    = c.stay_id
     AND m.starttime BETWEEN c.intime
                       AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.stay_id
),
quint AS (
  SELECT
    m.*,
    NTILE(5) OVER (ORDER BY med_count) AS quintile
  FROM meds m
),
readmissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    EXISTS(
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a.subject_id
        AND a2.admittime  > a.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
    ) AS readmit30
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE
    EXISTS (
      SELECT 1 FROM quint q
      WHERE q.hadm_id = a.hadm_id
    )
),
summary AS (
  SELECT
    q.quintile,
    COUNT(*)                             AS n_stays,
    AVG(c.los)                           AS avg_icu_los,
    AVG(IF(c.hospital_expire_flag=1,1,0)) AS mort_rate,
    AVG(IF(r.readmit30,1,0))             AS readmit_rate
  FROM
    quint q
    JOIN cohort c
      USING(subject_id, hadm_id, stay_id)
    LEFT JOIN readmissions r
      USING(subject_id, hadm_id)
  GROUP BY
    q.quintile
),
my_patient AS (
  SELECT
    q.subject_id,
    q.hadm_id,
    q.stay_id,
    q.med_count,
    q.quintile
  FROM
    quint q
    JOIN cohort c
      USING(subject_id, hadm_id, stay_id)
  WHERE
    c.anchor_age = 42
)
SELECT
  s.*,
  '42-year-old male (quintile ' || CAST(m.quintile AS STRING) || ')' AS patient_label,
  m.med_count AS patient_med_count
FROM
  summary s
  LEFT JOIN my_patient m
    ON s.quintile = m.quintile
ORDER BY
  s.quintile;