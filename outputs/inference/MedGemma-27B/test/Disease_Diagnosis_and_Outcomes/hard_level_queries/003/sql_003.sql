SELECT
    pea.subject_id,
    pea.hadm_id,
    DATETIME_DIFF(pea.dischtime, pea.admittime, DAY) AS los
  FROM PE_Admissions AS pea
  JOIN Mortality AS m
    ON pea.subject_id = m.subject_id AND pea.hadm_id = m.hadm_id
  WHERE
    m.mortality_90_day = 0
);