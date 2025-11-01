WITH female_59_69 AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        p.gender,
        p.anchor_age,
        a.admittime,
        a.dischtime,
        a.deathtime,
        p.dod,
        LEAST(p.dod, a.deathtime) AS death_date
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 59 AND 69
),
cardiac_arrest AS (
    SELECT DISTINCT
        f.*,
        -- Placeholder composite risk score; replace with real calculation
        RAND() AS risk_score
    FROM female_59_69 f
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON f.subject_id = di.subject_id AND f.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE UPPER(dd.long_title) LIKE '%CARDIAC ARREST%'
),
quartiled AS (
    SELECT
        ca.*,
        NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
    FROM cardiac_arrest ca
),
complications AS (
    SELECT
        q.hadm_id,
        MAX(CASE WHEN UPPER(dd.long_title) LIKE '%CARDIAC%' 
                     OR UPPER(dd.long_title) LIKE '%MYOCARD%' 
                     OR UPPER(dd.long_title) LIKE '%HEART%' 
                     OR UPPER(dd.long_title) LIKE '%INFARCT%'
                     THEN 1 ELSE 0 END) AS cv_complication,
        MAX(CASE WHEN UPPER(dd.long_title) LIKE '%STROKE%' 
                     OR UPPER(dd.long_title) LIKE '%BRAIN%' 
                     OR UPPER(dd.long_title) LIKE '%CEREBR%' 
                     OR UPPER(dd.long_title) LIKE '%ENCEPHAL%' 
                     OR UPPER(dd.long_title) LIKE '%SEIZURE%'
                     THEN 1 ELSE 0 END) AS neuro_complication
    FROM quartiled q
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON q.subject_id = di.subject_id AND q.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    GROUP BY q.hadm_id
),
quartile_outcomes AS (
    SELECT
        q.risk_quartile,
        COUNT(DISTINCT q.hadm_id) AS n_patients,
        AVG(CASE WHEN q.death_date IS NOT NULL 
                     AND q.death_date <= q.admittime + INTERVAL 30 DAY
                 THEN 1 ELSE 0 END) AS mortality_30d,
        AVG(c.cv_complication) AS cv_comp_rate,
        AVG(c.neuro_complication) AS neuro_comp_rate,
        -- Median survivor LOS in days
        APPROX_QUANTILES(
            CASE WHEN q.death_date IS NULL 
                      OR q.death_date > q.admittime + INTERVAL 30 DAY
                 THEN DATE_DIFF(DATE(q.dischtime), DATE(q.admittime), DAY)
            END, 2
        )[OFFSET(1)] AS median_survivor_los_days
    FROM quartiled q
    LEFT JOIN complications c
      ON q.hadm_id = c.hadm_id
    GROUP BY q.risk_quartile
),
baseline_mortality AS (
    SELECT
        AVG(CASE WHEN f.death_date IS NOT NULL
                     AND f.death_date <= f.admittime + INTERVAL 30 DAY
                 THEN 1 ELSE 0 END) AS baseline_30d_mortality
    FROM female_59_69 f
)
SELECT
    qo.*,
    b.baseline_30d_mortality
FROM quartile_outcomes qo
CROSS JOIN baseline_mortality b
ORDER BY risk_quartile;